// Supabase Client Configuration
// Replace these values with your own Supabase project credentials

const SUPABASE_URL = 'https://pjosgmvhlaavmuaigzon.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBqb3NnbXZobGFhdm11YWlnem9uIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ2ODY3NDUsImV4cCI6MjA4MDI2Mjc0NX0.Y0p3vvFQbAYB4tMFXBCIoOKBbMnMOCDH7FF8AtBhDKk';

// Initialize Supabase client (loaded from CDN in HTML)
let supabase;

function initSupabase() {
    if (typeof window.supabase !== 'undefined') {
        supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
        return true;
    }
    console.error('Supabase library not loaded');
    return false;
}

// Database operations using secure RPC functions
const db = {
    // Create a new group with participants
    async createGroup(groupName, participantNames, maxExclusions) {
        const { data, error } = await supabase.rpc('create_group', {
            p_name: groupName,
            p_participant_names: participantNames,
            p_max_exclusions: maxExclusions
        });

        if (error) throw error;
        return data;
    },

    // Get group by admin token
    async getGroupByAdminToken(adminToken) {
        const { data, error } = await supabase.rpc('get_group_by_admin_token', {
            p_admin_token: adminToken
        });

        if (error) throw error;
        return data;
    },

    // Get participant by token
    async getParticipantByToken(token) {
        const { data, error } = await supabase.rpc('get_participant_by_token', {
            p_token: token
        });

        if (error) throw error;
        return data;
    },

    // Get participants with exclusions for assignment algorithm (admin only)
    async getParticipantsForAssignment(adminToken) {
        const { data, error } = await supabase.rpc('get_participants_for_assignment', {
            p_admin_token: adminToken
        });

        if (error) throw error;
        return data;
    },

    // Submit exclusions for a participant
    async submitExclusions(participantToken, exclusions) {
        const { data, error } = await supabase.rpc('submit_exclusions', {
            p_token: participantToken,
            p_exclusions: exclusions
        });

        if (error) throw error;
        return data;
    },

    // Update group status (admin only)
    async updateGroupStatus(adminToken, status) {
        const { data, error } = await supabase.rpc('update_group_status', {
            p_admin_token: adminToken,
            p_status: status
        });

        if (error) throw error;
        return data;
    },

    // Save assignments (admin only)
    async saveAssignments(adminToken, assignments) {
        const { data, error } = await supabase.rpc('save_assignments', {
            p_admin_token: adminToken,
            p_assignments: assignments
        });

        if (error) throw error;
        return data;
    },

    // Mark group as assigned (convenience wrapper)
    async markGroupAssigned(adminToken) {
        return this.updateGroupStatus(adminToken, 'assigned');
    }
};

// Export for use in other modules
window.db = db;
window.initSupabase = initSupabase;
