-- CDC Demo: Seed data
-- Run after init.sql to generate change events

INSERT INTO customers (name, email) VALUES
    ('Alice Johnson', 'alice@example.com'),
    ('Bob Smith', 'bob@example.com'),
    ('Carol White', 'carol@example.com');

INSERT INTO orders (customer_id, product, amount, status) VALUES
    (1, 'Streamline Pro License', 99.00, 'completed'),
    (2, 'Streamline Enterprise', 499.00, 'pending'),
    (1, 'Support Plan', 29.99, 'completed'),
    (3, 'Streamline Pro License', 99.00, 'completed'),
    (2, 'Consulting Hours', 150.00, 'pending');

-- Generate an update event
UPDATE orders SET status = 'completed' WHERE id = 2;

-- Generate a delete event
DELETE FROM orders WHERE id = 5;
