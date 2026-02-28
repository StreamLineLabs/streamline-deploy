# Tutorial 2: Consumer Groups

Learn how consumer groups enable parallel processing and automatic load balancing.

## Step 1: Create a Topic with Data

```bash
streamline-cli topics create orders --partitions 6
streamline-cli produce orders --template '{"order_id": "ORD-{{i}}", "amount": {{random:10:500}}}' -n 1000
```

## Step 2: Start Consumer Group

```bash
# Terminal 1: First consumer
streamline-cli consume orders --group order-processors -f

# Terminal 2: Second consumer (partitions rebalance automatically)
streamline-cli consume orders --group order-processors -f
```

## Step 3: Monitor Consumer Lag

```bash
streamline-cli groups describe order-processors
```

## Step 4: Reset Offsets

```bash
# Dry run
streamline-cli groups reset order-processors -t orders --to-earliest

# Execute
streamline-cli groups reset order-processors -t orders --to-earliest --execute
```
