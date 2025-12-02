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

// Database operations
const db = {
    // Create a new group with participants
    async createGroup(groupName, participantNames, maxExclusions) {
        // Create the group
        const { data: group, error: groupError } = await supabase
            .from('groups')
            .insert({
                name: groupName,
                max_exclusions: maxExclusions
            })
            .select()
            .single();

        if (groupError) throw groupError;

        // Create participants
        const participants = participantNames.map(name => ({
            group_id: group.id,
            name: name.trim()
        }));

        const { data: createdParticipants, error: participantsError } = await supabase
            .from('participants')
            .insert(participants)
            .select();

        if (participantsError) throw participantsError;

        return {
            group,
            participants: createdParticipants
        };
    },

    // Get group by admin token
    async getGroupByAdminToken(adminToken) {
        const { data, error } = await supabase
            .from('groups')
            .select('*, participants(*)')
            .eq('admin_token', adminToken)
            .single();

        if (error) throw error;
        return data;
    },

    // Get participant by token
    async getParticipantByToken(token) {
        const { data, error } = await supabase
            .from('participants')
            .select('*, groups(*)')
            .eq('participant_token', token)
            .single();

        if (error) throw error;
        return data;
    },

    // Get all participants in a group
    async getGroupParticipants(groupId) {
        const { data, error } = await supabase
            .from('participants')
            .select('*')
            .eq('group_id', groupId);

        if (error) throw error;
        return data;
    },

    // Submit exclusions for a participant
    async submitExclusions(participantToken, exclusions) {
        const { data, error } = await supabase
            .from('participants')
            .update({
                exclusions: exclusions,
                has_submitted: true
            })
            .eq('participant_token', participantToken)
            .select()
            .single();

        if (error) throw error;
        return data;
    },

    // Update group status
    async updateGroupStatus(groupId, status) {
        const { data, error } = await supabase
            .from('groups')
            .update({ status })
            .eq('id', groupId)
            .select()
            .single();

        if (error) throw error;
        return data;
    },

    // Save assignments
    async saveAssignments(assignments) {
        // assignments is an array of { participantId, assignedTo }
        const updates = assignments.map(async ({ participantId, assignedTo }) => {
            return supabase
                .from('participants')
                .update({ assigned_to: assignedTo })
                .eq('id', participantId);
        });

        await Promise.all(updates);
    },

    // Update group status to assigned
    async markGroupAssigned(groupId) {
        return this.updateGroupStatus(groupId, 'assigned');
    }
};

// Export for use in other modules
window.db = db;
window.initSupabase = initSupabase;
