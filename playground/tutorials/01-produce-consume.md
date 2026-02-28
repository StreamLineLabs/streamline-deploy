# Tutorial 1: Produce and Consume Messages

Welcome to Streamline! In this tutorial, you'll learn to produce and consume messages in under 2 minutes.

## Step 1: Create a Topic

```bash
streamline-cli topics create my-first-topic --partitions 3
```

Expected output:
```
✅ Topic 'my-first-topic' created with 3 partitions
```

## Step 2: Produce Messages

```bash
# Single message
streamline-cli produce my-first-topic -m '{"user": "alice", "action": "login"}'

# Multiple messages with a template
streamline-cli produce my-first-topic \
  --template '{"user": "user-{{i}}", "ts": {{timestamp}}}' \
  -n 100
```

## Step 3: Consume Messages

```bash
# From the beginning
streamline-cli consume my-first-topic --from-beginning -n 5

# Follow new messages (like tail -f)
streamline-cli consume my-first-topic -f

# Filter by content
streamline-cli consume my-first-topic --grep "alice" --from-beginning
```

## Step 4: View the Dashboard

```bash
streamline-cli top
```

This opens an interactive TUI showing real-time throughput, partitions, and consumer lag.

## What's Next?
- [Tutorial 2: Consumer Groups](02-consumer-groups.md)
- [Tutorial 3: CDC from PostgreSQL](03-cdc-postgres.md)
