# Migrating from Kafka TestContainers to Streamline

## Why Migrate?

| Metric | Kafka TestContainers | Streamline TestContainers |
|--------|---------------------|--------------------------|
| **Cold start** | 30-60 seconds | <100 milliseconds |
| **Memory usage** | 500MB+ (JVM) | <50MB |
| **Docker image** | ~800MB (cp-kafka) | <20MB |
| **Dependencies** | ZooKeeper/KRaft | None |
| **API compatible** | N/A (is Kafka) | 50+ Kafka APIs |

## Migration Steps

### Java (JUnit 5)

**Before (Kafka):**
```java
import org.testcontainers.kafka.KafkaContainer;

@Container
static KafkaContainer kafka = new KafkaContainer(
    DockerImageName.parse("confluentinc/cp-kafka:7.6.0")
);

String bootstrap = kafka.getBootstrapServers();
```

**After (Streamline):**
```java
import io.streamline.testcontainers.StreamlineContainer;

@Container
static StreamlineContainer streamline = StreamlineContainer.forTesting();

String bootstrap = streamline.getBootstrapServers();
// All your Kafka client code works unchanged!
```

### Python (pytest)

**Before:**
```python
from testcontainers.kafka import KafkaContainer

@pytest.fixture(scope="session")
def kafka():
    with KafkaContainer() as container:
        yield container
```

**After:**
```python
from streamline_testcontainers import StreamlineContainer

@pytest.fixture(scope="session")
def streamline():
    with StreamlineContainer.for_testing() as container:
        yield container
```

### Go

**Before:**
```go
container, _ := kafka.RunContainer(ctx)
brokers, _ := container.Brokers(ctx)
```

**After:**
```go
container, _ := streamlinetc.RunForTesting(ctx)
brokers, _ := container.BootstrapServers(ctx)
```

### Node.js / TypeScript

**Before:**
```typescript
const kafka = await new KafkaContainer().start();
const bootstrap = kafka.getBootstrapServers();
```

**After:**
```typescript
const streamline = await StreamlineContainer.forTesting();
const bootstrap = streamline.getBootstrapServers();
```

## Ephemeral Mode (Streamline-specific)

Streamline's `--ephemeral` mode provides additional CI/CD optimizations:

```java
// Auto-create topics, auto-shutdown on idle
StreamlineContainer container = StreamlineContainer.forTesting()
    .withEphemeralAutoTopics("orders:3,events:6,logs:1")
    .withEphemeralIdleTimeout(10);
```

## FAQ

**Q: Will my existing Kafka client tests work?**
A: Yes. Streamline implements 50+ Kafka APIs. Your existing
   `KafkaProducer`, `KafkaConsumer`, `AdminClient` code works unchanged.

**Q: What about schema registry?**
A: Streamline has a built-in Confluent-compatible schema registry.
   Point your schema registry URL to `http://streamline:9094`.

**Q: Can I use Kafka Connect?**
A: Streamline implements the Kafka Connect REST API.
   Your connector configurations work unchanged.
