-- Shared by both native clients. Reservations are never refunded after an
-- upstream error: a failed provider request may still count toward quota.
CREATE TABLE nearby_request_budget (
  month TEXT PRIMARY KEY,
  day TEXT NOT NULL,
  month_used INTEGER NOT NULL CHECK(month_used >= 0),
  day_used INTEGER NOT NULL CHECK(day_used >= 0)
);
