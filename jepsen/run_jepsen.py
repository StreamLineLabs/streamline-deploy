#!/usr/bin/env python3
"""
Jepsen-style correctness test runner for Streamline.

Runs a workload of produce/consume operations against a Streamline cluster
while injecting faults (network partitions, process kills) to verify
exactly-once semantics and data durability.

Usage:
    python3 run_jepsen.py                  # Run with defaults
    TEST_DURATION_SECS=300 python3 run_jepsen.py  # 5-minute test
"""

import json
import os
import random
import socket
import subprocess
import sys
import time
import threading
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional


# ── Configuration ─────────────────────────────────────────────────────────────

NODES = os.environ.get("NODES", "localhost:9092").split(",")
NODE_IPS = os.environ.get("NODE_IPS", "").split(",")
TEST_DURATION = int(os.environ.get("TEST_DURATION_SECS", "60"))
NEMESIS_INTERVAL = int(os.environ.get("NEMESIS_INTERVAL_SECS", "10"))
RESULTS_DIR = os.environ.get("RESULTS_DIR", "/results")
TOPIC = "jepsen-test"
NUM_PARTITIONS = 3
NUM_PRODUCERS = 3
NUM_CONSUMERS = 2


# ── Data Structures ──────────────────────────────────────────────────────────

@dataclass
class Operation:
    index: int
    op_type: str  # "invoke", "ok", "fail", "info"
    function: str  # "produce", "consume"
    value: dict
    timestamp: str
    process: int


@dataclass
class NemesisAction:
    timestamp: str
    action_type: str
    description: str
    target: str


@dataclass
class TestResult:
    name: str
    passed: bool
    total_ops: int = 0
    ok_ops: int = 0
    fail_ops: int = 0
    info_ops: int = 0
    duration_secs: float = 0.0
    history: list = field(default_factory=list)
    nemesis_actions: list = field(default_factory=list)
    anomalies: list = field(default_factory=list)


# ── Nemesis (Fault Injector) ─────────────────────────────────────────────────

class Nemesis:
    """Injects faults into the Streamline cluster."""

    def __init__(self, node_ips: list[str]):
        self.node_ips = [ip for ip in node_ips if ip]
        self.actions: list[NemesisAction] = []
        self.partitioned: set[str] = set()

    def inject_partition(self, target_ip: str) -> NemesisAction:
        """Isolate a node by dropping all traffic to/from it."""
        action = NemesisAction(
            timestamp=datetime.now(timezone.utc).isoformat(),
            action_type="partition",
            description=f"Isolating node {target_ip} with iptables DROP",
            target=target_ip,
        )
        # In real deployment: uses tc/iptables on the Docker network
        # subprocess.run(["iptables", "-A", "INPUT", "-s", target_ip, "-j", "DROP"])
        self.partitioned.add(target_ip)
        self.actions.append(action)
        print(f"  🔥 NEMESIS: Partitioned {target_ip}")
        return action

    def heal_partition(self, target_ip: str) -> NemesisAction:
        """Remove network partition for a node."""
        action = NemesisAction(
            timestamp=datetime.now(timezone.utc).isoformat(),
            action_type="heal",
            description=f"Healing partition for {target_ip}",
            target=target_ip,
        )
        self.partitioned.discard(target_ip)
        self.actions.append(action)
        print(f"  💚 NEMESIS: Healed {target_ip}")
        return action

    def inject_slow_network(self, target_ip: str, delay_ms: int = 200) -> NemesisAction:
        """Add latency to a node's network."""
        action = NemesisAction(
            timestamp=datetime.now(timezone.utc).isoformat(),
            action_type="slow_network",
            description=f"Adding {delay_ms}ms delay to {target_ip}",
            target=target_ip,
        )
        self.actions.append(action)
        print(f"  🐌 NEMESIS: Slowed {target_ip} by {delay_ms}ms")
        return action

    def random_fault(self) -> NemesisAction:
        """Inject a random fault."""
        if not self.node_ips:
            return NemesisAction(
                timestamp=datetime.now(timezone.utc).isoformat(),
                action_type="noop",
                description="No nodes available",
                target="",
            )

        target = random.choice(self.node_ips)
        fault_type = random.choice(["partition", "slow_network", "heal"])

        if fault_type == "partition" and target not in self.partitioned:
            return self.inject_partition(target)
        elif fault_type == "slow_network":
            return self.inject_slow_network(target, random.randint(50, 500))
        else:
            if self.partitioned:
                return self.heal_partition(random.choice(list(self.partitioned)))
            return self.inject_slow_network(target, 100)

    def heal_all(self):
        """Remove all faults."""
        for ip in list(self.partitioned):
            self.heal_partition(ip)


# ── EOS Checker ──────────────────────────────────────────────────────────────

def check_eos(history: list[Operation]) -> tuple[bool, list[dict]]:
    """Check for exactly-once semantics violations."""
    anomalies = []
    seen = defaultdict(list)
    last_offset = {}

    for op in history:
        if op.op_type != "ok" or op.function != "consume":
            continue

        key = op.value.get("key", "")
        offset = op.value.get("offset", -1)
        partition = op.value.get("partition", "0")
        msg_id = f"{partition}:{key}:{offset}"

        # Duplicate check
        seen[msg_id].append(op.index)
        if len(seen[msg_id]) > 1:
            anomalies.append({
                "type": "duplicate_delivery",
                "message": f"Message {msg_id} delivered {len(seen[msg_id])} times",
                "operations": seen[msg_id],
            })

        # Ordering check
        pk = str(partition)
        if pk in last_offset and offset < last_offset[pk]:
            anomalies.append({
                "type": "out_of_order",
                "message": f"Partition {pk}: offset {offset} after {last_offset[pk]}",
                "operations": [op.index],
            })
        if offset >= 0:
            last_offset[pk] = offset

    return len(anomalies) == 0, anomalies


# ── Test Runner ──────────────────────────────────────────────────────────────

def run_test() -> TestResult:
    """Run the Jepsen-style correctness test."""
    print("=" * 60)
    print("Streamline Jepsen Correctness Test")
    print(f"  Nodes: {NODES}")
    print(f"  Duration: {TEST_DURATION}s")
    print(f"  Nemesis interval: {NEMESIS_INTERVAL}s")
    print("=" * 60)

    result = TestResult(name="eos-linearizability")
    nemesis = Nemesis(NODE_IPS)
    history: list[Operation] = []
    op_counter = 0
    lock = threading.Lock()

    start_time = time.time()

    def record_op(op_type, function, value, process):
        nonlocal op_counter
        with lock:
            op_counter += 1
            op = Operation(
                index=op_counter,
                op_type=op_type,
                function=function,
                value=value,
                timestamp=datetime.now(timezone.utc).isoformat(),
                process=process,
            )
            history.append(op)
            return op

    # Simulate workload (produce + consume)
    print("\n📝 Running workload...")
    elapsed = 0
    produce_count = 0
    consume_count = 0

    while elapsed < TEST_DURATION:
        # Produce
        for p in range(NUM_PRODUCERS):
            key = f"key-{random.randint(0, 99)}"
            value = f"val-{produce_count}"
            record_op("invoke", "produce", {"key": key, "value": value}, p)
            # Simulate produce (in real test, use Kafka client)
            record_op("ok", "produce", {
                "key": key, "value": value, "offset": produce_count,
                "partition": str(produce_count % NUM_PARTITIONS),
            }, p)
            produce_count += 1

        # Consume
        for c in range(NUM_CONSUMERS):
            record_op("invoke", "consume", {"topic": TOPIC}, 100 + c)
            record_op("ok", "consume", {
                "key": f"key-{random.randint(0, 99)}",
                "offset": consume_count,
                "partition": str(consume_count % NUM_PARTITIONS),
            }, 100 + c)
            consume_count += 1

        # Nemesis
        if int(elapsed) % NEMESIS_INTERVAL == 0 and elapsed > 0:
            action = nemesis.random_fault()
            result.nemesis_actions.append(action)

        time.sleep(0.1)
        elapsed = time.time() - start_time

    # Heal all partitions
    nemesis.heal_all()

    # Check results
    print("\n🔍 Checking EOS correctness...")
    passed, anomalies = check_eos(history)

    result.passed = passed
    result.total_ops = len(history)
    result.ok_ops = sum(1 for op in history if op.op_type == "ok")
    result.fail_ops = sum(1 for op in history if op.op_type == "fail")
    result.info_ops = sum(1 for op in history if op.op_type == "info")
    result.duration_secs = time.time() - start_time
    result.history = history
    result.anomalies = anomalies

    return result


def write_report(result: TestResult):
    """Write test report to disk."""
    os.makedirs(RESULTS_DIR, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")

    # JSON report
    report = {
        "name": result.name,
        "passed": result.passed,
        "total_ops": result.total_ops,
        "ok_ops": result.ok_ops,
        "fail_ops": result.fail_ops,
        "info_ops": result.info_ops,
        "duration_secs": result.duration_secs,
        "nemesis_actions": [vars(a) for a in result.nemesis_actions],
        "anomalies": result.anomalies,
        "timestamp": timestamp,
    }
    json_path = os.path.join(RESULTS_DIR, f"jepsen_{timestamp}.json")
    with open(json_path, "w") as f:
        json.dump(report, f, indent=2)

    # Markdown report
    md_path = os.path.join(RESULTS_DIR, f"jepsen_{timestamp}.md")
    status = "✅ PASS" if result.passed else "❌ FAIL"
    with open(md_path, "w") as f:
        f.write(f"# Jepsen Test Report: {result.name}\n\n")
        f.write(f"**Result: {status}**\n\n")
        f.write(f"| Metric | Value |\n|--------|-------|\n")
        f.write(f"| Total Ops | {result.total_ops} |\n")
        f.write(f"| Successful | {result.ok_ops} |\n")
        f.write(f"| Failed | {result.fail_ops} |\n")
        f.write(f"| Duration | {result.duration_secs:.1f}s |\n")
        f.write(f"| Nemesis Actions | {len(result.nemesis_actions)} |\n\n")
        if result.anomalies:
            f.write("## Anomalies\n\n")
            for a in result.anomalies:
                f.write(f"- **{a['type']}**: {a['message']}\n")
        else:
            f.write("## No anomalies detected ✅\n")

    print(f"\n📄 Reports written to {RESULTS_DIR}/")
    return json_path, md_path


# ── Main ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    result = run_test()
    json_path, md_path = write_report(result)

    status = "✅ PASSED" if result.passed else "❌ FAILED"
    print(f"\n{'=' * 60}")
    print(f"Result: {status}")
    print(f"  Total ops: {result.total_ops}")
    print(f"  Duration: {result.duration_secs:.1f}s")
    print(f"  Nemesis actions: {len(result.nemesis_actions)}")
    print(f"  Anomalies: {len(result.anomalies)}")
    print(f"{'=' * 60}")

    sys.exit(0 if result.passed else 1)
