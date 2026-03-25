-- Initialize the database schema
CREATE TABLE IF NOT EXISTS ziex (
    id SERIAL PRIMARY KEY,
    count BIGINT NOT NULL
);