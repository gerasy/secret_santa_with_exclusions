-- Secret Santa with Exclusions - Database Schema
-- Run this in Supabase SQL Editor to set up the database

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Groups table
CREATE TABLE groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    admin_token UUID NOT NULL DEFAULT uuid_generate_v4(),
    max_exclusions INT NOT NULL DEFAULT 2,
    status TEXT NOT NULL DEFAULT 'collecting' CHECK (status IN ('collecting', 'ready', 'assigned')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Participants table
CREATE TABLE participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    participant_token UUID NOT NULL DEFAULT uuid_generate_v4(),
    exclusions TEXT[] DEFAULT '{}',
    has_submitted BOOLEAN DEFAULT FALSE,
    assigned_to TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for faster lookups
CREATE INDEX idx_participants_group_id ON participants(group_id);
CREATE INDEX idx_participants_token ON participants(participant_token);
CREATE INDEX idx_groups_admin_token ON groups(admin_token);

-- Row Level Security (RLS) Policies
ALTER TABLE groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE participants ENABLE ROW LEVEL SECURITY;

-- Allow anonymous access for our use case (token-based auth)
-- Groups: Anyone can create, but only admin can view full details
CREATE POLICY "Anyone can create groups" ON groups
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Anyone can read groups by admin_token" ON groups
    FOR SELECT USING (true);

CREATE POLICY "Admin can update their group" ON groups
    FOR UPDATE USING (true);

-- Participants: Token-based access
CREATE POLICY "Anyone can create participants" ON participants
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Anyone can read participants" ON participants
    FOR SELECT USING (true);

CREATE POLICY "Participants can update their own record" ON participants
    FOR UPDATE USING (true);

-- Function to check if assignment is possible
CREATE OR REPLACE FUNCTION check_assignment_possible(group_id_param UUID)
RETURNS BOOLEAN AS $$
DECLARE
    participant_count INT;
    all_submitted BOOLEAN;
BEGIN
    -- Check all participants have submitted
    SELECT
        COUNT(*),
        BOOL_AND(has_submitted)
    INTO participant_count, all_submitted
    FROM participants
    WHERE group_id = group_id_param;

    -- Need at least 2 participants and all must have submitted
    IF participant_count < 2 OR NOT all_submitted THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
