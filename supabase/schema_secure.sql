-- Secret Santa with Exclusions - SECURE Database Schema
-- Run this in Supabase SQL Editor to set up the database
-- This version uses RPC functions to protect data access

-- ============================================
-- STEP 1: Drop existing objects (if upgrading)
-- ============================================
DROP FUNCTION IF EXISTS create_group(TEXT, TEXT[], INT);
DROP FUNCTION IF EXISTS get_group_by_admin_token(UUID);
DROP FUNCTION IF EXISTS get_participant_by_token(UUID);
DROP FUNCTION IF EXISTS get_group_participants_for_participant(UUID);
DROP FUNCTION IF EXISTS submit_exclusions(UUID, TEXT[]);
DROP FUNCTION IF EXISTS update_group_status(UUID, TEXT);
DROP FUNCTION IF EXISTS save_assignments(UUID, JSONB);

DROP POLICY IF EXISTS "Anyone can create groups" ON groups;
DROP POLICY IF EXISTS "Anyone can read groups by admin_token" ON groups;
DROP POLICY IF EXISTS "Admin can update their group" ON groups;
DROP POLICY IF EXISTS "Read groups by admin_token" ON groups;
DROP POLICY IF EXISTS "Update groups by admin_token" ON groups;
DROP POLICY IF EXISTS "Anyone can create participants" ON participants;
DROP POLICY IF EXISTS "Anyone can read participants" ON participants;
DROP POLICY IF EXISTS "Participants can update their own record" ON participants;
DROP POLICY IF EXISTS "Read own participant by token" ON participants;
DROP POLICY IF EXISTS "Update own participant by token" ON participants;
DROP POLICY IF EXISTS "Deny all direct access to groups" ON groups;
DROP POLICY IF EXISTS "Deny all direct access to participants" ON participants;

DROP TABLE IF EXISTS participants;
DROP TABLE IF EXISTS groups;

-- ============================================
-- STEP 2: Create tables
-- ============================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    admin_token UUID NOT NULL DEFAULT uuid_generate_v4(),
    max_exclusions INT NOT NULL DEFAULT 2,
    status TEXT NOT NULL DEFAULT 'collecting' CHECK (status IN ('collecting', 'ready', 'assigned')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

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

CREATE INDEX idx_participants_group_id ON participants(group_id);
CREATE INDEX idx_participants_token ON participants(participant_token);
CREATE INDEX idx_groups_admin_token ON groups(admin_token);

-- ============================================
-- STEP 3: Enable RLS and DENY all direct access
-- ============================================
ALTER TABLE groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE participants ENABLE ROW LEVEL SECURITY;

-- Block all direct table access - force use of RPC functions
CREATE POLICY "Deny all direct access to groups" ON groups
    FOR ALL USING (false);

CREATE POLICY "Deny all direct access to participants" ON participants
    FOR ALL USING (false);

-- ============================================
-- STEP 4: Create secure RPC functions
-- ============================================

-- 4.1 CREATE GROUP (public - anyone can create)
CREATE OR REPLACE FUNCTION create_group(
    p_name TEXT,
    p_participant_names TEXT[],
    p_max_exclusions INT DEFAULT 2
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_group_id UUID;
    v_admin_token UUID;
    v_result JSONB;
    v_participants JSONB := '[]'::JSONB;
    v_participant_name TEXT;
    v_participant_id UUID;
    v_participant_token UUID;
BEGIN
    -- Validate inputs
    IF p_name IS NULL OR LENGTH(TRIM(p_name)) = 0 THEN
        RAISE EXCEPTION 'Group name is required';
    END IF;

    IF p_participant_names IS NULL OR array_length(p_participant_names, 1) < 2 THEN
        RAISE EXCEPTION 'At least 2 participants are required';
    END IF;

    IF p_max_exclusions < 0 THEN
        RAISE EXCEPTION 'Max exclusions cannot be negative';
    END IF;

    -- Create the group
    INSERT INTO groups (name, max_exclusions)
    VALUES (TRIM(p_name), p_max_exclusions)
    RETURNING id, admin_token INTO v_group_id, v_admin_token;

    -- Create participants
    FOREACH v_participant_name IN ARRAY p_participant_names
    LOOP
        INSERT INTO participants (group_id, name)
        VALUES (v_group_id, TRIM(v_participant_name))
        RETURNING id, participant_token INTO v_participant_id, v_participant_token;

        v_participants := v_participants || jsonb_build_object(
            'id', v_participant_id,
            'name', TRIM(v_participant_name),
            'participant_token', v_participant_token
        );
    END LOOP;

    -- Build result
    v_result := jsonb_build_object(
        'group', jsonb_build_object(
            'id', v_group_id,
            'name', TRIM(p_name),
            'admin_token', v_admin_token,
            'max_exclusions', p_max_exclusions,
            'status', 'collecting'
        ),
        'participants', v_participants
    );

    RETURN v_result;
END;
$$;

-- 4.2 GET GROUP BY ADMIN TOKEN (admin only)
-- Returns group + participants (with tokens for sharing, but WITHOUT exclusions)
CREATE OR REPLACE FUNCTION get_group_by_admin_token(p_admin_token UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_group RECORD;
    v_participants JSONB;
BEGIN
    -- Get the group
    SELECT * INTO v_group
    FROM groups
    WHERE admin_token = p_admin_token;

    IF v_group IS NULL THEN
        RAISE EXCEPTION 'Group not found or invalid admin token';
    END IF;

    -- Get participants (WITHOUT exclusions for privacy)
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', p.id,
            'name', p.name,
            'participant_token', p.participant_token,
            'has_submitted', p.has_submitted,
            'assigned_to', p.assigned_to
        )
    ), '[]'::JSONB)
    INTO v_participants
    FROM participants p
    WHERE p.group_id = v_group.id;

    RETURN jsonb_build_object(
        'id', v_group.id,
        'name', v_group.name,
        'admin_token', v_group.admin_token,
        'max_exclusions', v_group.max_exclusions,
        'status', v_group.status,
        'participants', v_participants
    );
END;
$$;

-- 4.3 GET PARTICIPANT BY TOKEN (participant only - sees own data)
CREATE OR REPLACE FUNCTION get_participant_by_token(p_token UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_participant RECORD;
    v_group RECORD;
    v_other_participants JSONB;
BEGIN
    -- Get the participant
    SELECT * INTO v_participant
    FROM participants
    WHERE participant_token = p_token;

    IF v_participant IS NULL THEN
        RAISE EXCEPTION 'Participant not found or invalid token';
    END IF;

    -- Get the group
    SELECT * INTO v_group
    FROM groups
    WHERE id = v_participant.group_id;

    -- Get other participants (names only - for exclusion selection)
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', p.id,
            'name', p.name
        )
    ), '[]'::JSONB)
    INTO v_other_participants
    FROM participants p
    WHERE p.group_id = v_participant.group_id
    AND p.id != v_participant.id;

    RETURN jsonb_build_object(
        'id', v_participant.id,
        'name', v_participant.name,
        'exclusions', v_participant.exclusions,
        'has_submitted', v_participant.has_submitted,
        'assigned_to', v_participant.assigned_to,
        'group', jsonb_build_object(
            'id', v_group.id,
            'name', v_group.name,
            'max_exclusions', v_group.max_exclusions,
            'status', v_group.status
        ),
        'other_participants', v_other_participants
    );
END;
$$;

-- 4.4 SUBMIT EXCLUSIONS (participant only)
CREATE OR REPLACE FUNCTION submit_exclusions(p_token UUID, p_exclusions TEXT[])
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_participant RECORD;
    v_group RECORD;
    v_max_exclusions INT;
BEGIN
    -- Get the participant
    SELECT * INTO v_participant
    FROM participants
    WHERE participant_token = p_token;

    IF v_participant IS NULL THEN
        RAISE EXCEPTION 'Participant not found or invalid token';
    END IF;

    -- Get max exclusions from group
    SELECT max_exclusions INTO v_max_exclusions
    FROM groups
    WHERE id = v_participant.group_id;

    -- Validate exclusions count
    IF p_exclusions IS NOT NULL AND array_length(p_exclusions, 1) > v_max_exclusions THEN
        RAISE EXCEPTION 'Too many exclusions. Maximum allowed: %', v_max_exclusions;
    END IF;

    -- Update the participant
    UPDATE participants
    SET exclusions = COALESCE(p_exclusions, '{}'),
        has_submitted = true
    WHERE participant_token = p_token;

    -- Return updated data
    RETURN get_participant_by_token(p_token);
END;
$$;

-- 4.5 UPDATE GROUP STATUS (admin only)
CREATE OR REPLACE FUNCTION update_group_status(p_admin_token UUID, p_status TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_group RECORD;
BEGIN
    -- Validate status
    IF p_status NOT IN ('collecting', 'ready', 'assigned') THEN
        RAISE EXCEPTION 'Invalid status. Must be: collecting, ready, or assigned';
    END IF;

    -- Get and verify the group
    SELECT * INTO v_group
    FROM groups
    WHERE admin_token = p_admin_token;

    IF v_group IS NULL THEN
        RAISE EXCEPTION 'Group not found or invalid admin token';
    END IF;

    -- Update status
    UPDATE groups
    SET status = p_status
    WHERE admin_token = p_admin_token;

    -- Return updated group
    RETURN get_group_by_admin_token(p_admin_token);
END;
$$;

-- 4.6 SAVE ASSIGNMENTS (admin only)
-- Expects JSONB array: [{"participant_id": "uuid", "assigned_to": "Name"}, ...]
CREATE OR REPLACE FUNCTION save_assignments(p_admin_token UUID, p_assignments JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_group RECORD;
    v_assignment JSONB;
    v_participant_id UUID;
    v_assigned_to TEXT;
BEGIN
    -- Get and verify the group
    SELECT * INTO v_group
    FROM groups
    WHERE admin_token = p_admin_token;

    IF v_group IS NULL THEN
        RAISE EXCEPTION 'Group not found or invalid admin token';
    END IF;

    -- Process each assignment
    FOR v_assignment IN SELECT * FROM jsonb_array_elements(p_assignments)
    LOOP
        v_participant_id := (v_assignment->>'participantId')::UUID;
        v_assigned_to := v_assignment->>'assignedTo';

        -- Verify participant belongs to this group
        IF NOT EXISTS (
            SELECT 1 FROM participants
            WHERE id = v_participant_id AND group_id = v_group.id
        ) THEN
            RAISE EXCEPTION 'Participant % does not belong to this group', v_participant_id;
        END IF;

        -- Update assignment
        UPDATE participants
        SET assigned_to = v_assigned_to
        WHERE id = v_participant_id;
    END LOOP;

    -- Update group status to assigned
    UPDATE groups
    SET status = 'assigned'
    WHERE admin_token = p_admin_token;

    -- Return updated group
    RETURN get_group_by_admin_token(p_admin_token);
END;
$$;

-- 4.7 GET GROUP PARTICIPANTS FOR ALGORITHM (admin only)
-- Returns participants WITH exclusions (needed for assignment algorithm)
CREATE OR REPLACE FUNCTION get_participants_for_assignment(p_admin_token UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_group RECORD;
    v_participants JSONB;
BEGIN
    -- Get and verify the group
    SELECT * INTO v_group
    FROM groups
    WHERE admin_token = p_admin_token;

    IF v_group IS NULL THEN
        RAISE EXCEPTION 'Group not found or invalid admin token';
    END IF;

    -- Get participants WITH exclusions (for algorithm only)
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', p.id,
            'name', p.name,
            'exclusions', p.exclusions,
            'has_submitted', p.has_submitted
        )
    ), '[]'::JSONB)
    INTO v_participants
    FROM participants p
    WHERE p.group_id = v_group.id;

    RETURN v_participants;
END;
$$;

-- ============================================
-- STEP 5: Grant execute permissions to anon role
-- ============================================
GRANT EXECUTE ON FUNCTION create_group(TEXT, TEXT[], INT) TO anon;
GRANT EXECUTE ON FUNCTION get_group_by_admin_token(UUID) TO anon;
GRANT EXECUTE ON FUNCTION get_participant_by_token(UUID) TO anon;
GRANT EXECUTE ON FUNCTION submit_exclusions(UUID, TEXT[]) TO anon;
GRANT EXECUTE ON FUNCTION update_group_status(UUID, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION save_assignments(UUID, JSONB) TO anon;
GRANT EXECUTE ON FUNCTION get_participants_for_assignment(UUID) TO anon;
