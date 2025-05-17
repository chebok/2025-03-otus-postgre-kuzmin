-- Drop existing tables for clean slate
DROP TABLE IF EXISTS fines;
DROP TABLE IF EXISTS locations;
DROP TABLE IF EXISTS rides;
DROP TABLE IF EXISTS cars;
DROP TABLE IF EXISTS users;

-- Users
CREATE TABLE users (
   id SERIAL PRIMARY KEY,
   name TEXT NOT NULL,
   registration_date DATE NOT NULL
);

CREATE INDEX idx_users_registration_date ON users(registration_date);

CREATE TABLE user_events (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    event_type TEXT CHECK (event_type IN ('support_call', 'manual_ban', 'feedback', 'unknown')),
    occurred_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_user_events_user_id ON user_events(user_id);


-- Cars
CREATE TABLE cars (
  id SERIAL PRIMARY KEY,
  model TEXT NOT NULL,
  status TEXT CHECK (status IN ('available', 'rented', 'maintenance')) NOT NULL
);

CREATE INDEX idx_cars_status ON cars(status);

-- Rides
CREATE TABLE rides (
   id SERIAL PRIMARY KEY,
   user_id INT NOT NULL REFERENCES users(id),
   car_id INT NOT NULL REFERENCES cars(id),
   started_at TIMESTAMP NOT NULL,
   ended_at TIMESTAMP,
   distance_km NUMERIC NOT NULL
);

CREATE INDEX idx_rides_id ON rides(id);
CREATE INDEX IF NOT EXISTS idx_rides_started_at ON rides(started_at);
CREATE INDEX idx_rides_user_id ON rides(user_id);

-- Fines
CREATE TABLE fines (
   id SERIAL PRIMARY KEY,
   ride_id INT NOT NULL REFERENCES rides(id),
   issued_at TIMESTAMP NOT NULL,
   amount NUMERIC NOT NULL
);

CREATE INDEX idx_fines_ride_id ON fines(ride_id);
CREATE INDEX idx_fines_issued_at ON fines(issued_at);

-- Locations
CREATE TABLE locations (
   id SERIAL PRIMARY KEY,
   car_id INT NOT NULL REFERENCES cars(id),
   updated_at TIMESTAMP NOT NULL,
   lat NUMERIC,
   lon NUMERIC
);

CREATE INDEX idx_locations_car_id ON locations(car_id);


-- Bulk insert users
INSERT INTO users (name, registration_date)
SELECT 'User_' || i, DATE '2023-01-01' + (i % 365)
FROM generate_series(1, 1000) AS i;

-- Bulk user events
INSERT INTO user_events (user_id, event_type, occurred_at)
SELECT
    floor(random() * 1000 + 1)::int, -- user_id от 1 до 1000
        (ARRAY['support_call', 'manual_ban', 'feedback', 'unknown'])[floor(random() * 4 + 1)],
    NOW() - (random() * interval '30 days')
FROM generate_series(1, 3000);

-- Bulk insert cars
INSERT INTO cars (model, status)
SELECT
    CASE WHEN i % 3 = 0 THEN 'Tesla Model 3'
         WHEN i % 3 = 1 THEN 'BMW i3'
         ELSE 'Nissan Leaf' END,
    CASE WHEN i % 5 = 0 THEN 'maintenance'
         WHEN i % 2 = 0 THEN 'rented'
         ELSE 'available' END
FROM generate_series(1, 300) AS i;

-- Bulk insert rides
INSERT INTO rides (user_id, car_id, started_at, ended_at, distance_km)
SELECT
    floor(random() * 1000 + 1)::int,
        floor(random() * 300 + 1)::int,
        NOW() - (random() * interval '30 days'),
    NOW() - (random() * interval '1 days'),
    round((random() * 30 + 1)::numeric, 2)
FROM generate_series(1, 100000);

-- Bulk insert fines (1 out of 5 rides get fined)
INSERT INTO fines (ride_id, issued_at, amount)
SELECT
    id,
    NOW() - (random() * interval '7 days'),
    round((random() * 500 + 100)::numeric, 2)
FROM rides
WHERE id % 5 = 0;

-- Bulk insert locations
INSERT INTO locations (car_id, updated_at, lat, lon)
SELECT
    id,
    NOW() - (random() * interval '10 minutes'),
    55.7 + random() * 0.1,
    37.5 + random() * 0.1
FROM cars;
