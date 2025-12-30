-- ============================================
-- Bifrost Kong Database Initialization
-- Only extensions and permissions - tables are created by Kong migrations
-- ============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Grant necessary permissions to kong user
-- (Tables will be created by Kong migrations, grants applied after they exist)
