// Secret Santa Assignment Algorithm
// Handles constraint satisfaction with exclusions

const SecretSantaAlgorithm = {
    /**
     * Check if a valid assignment is possible
     * @param {Array} participants - Array of participant objects with name and exclusions
     * @returns {Object} { possible: boolean, reason: string }
     */
    checkSolvable(participants) {
        const names = participants.map(p => p.name);
        const n = names.length;

        if (n < 2) {
            return { possible: false, reason: 'Need at least 2 participants' };
        }

        // Build adjacency matrix: canGiftTo[i][j] = true if i can gift to j
        const canGiftTo = [];
        for (let i = 0; i < n; i++) {
            canGiftTo[i] = [];
            const giver = participants[i];
            const excluded = new Set(giver.exclusions || []);

            for (let j = 0; j < n; j++) {
                const receiver = participants[j];
                // Can't gift to self, and can't gift to excluded people
                canGiftTo[i][j] = (i !== j) && !excluded.has(receiver.name);
            }
        }

        // Check if each person has at least one valid recipient
        for (let i = 0; i < n; i++) {
            const validRecipients = canGiftTo[i].filter(x => x).length;
            if (validRecipients === 0) {
                return {
                    possible: false,
                    reason: `${participants[i].name} has excluded too many people and has no one to gift to`
                };
            }
        }

        // Check if each person can receive from at least one person
        for (let j = 0; j < n; j++) {
            let canReceive = false;
            for (let i = 0; i < n; i++) {
                if (canGiftTo[i][j]) {
                    canReceive = true;
                    break;
                }
            }
            if (!canReceive) {
                return {
                    possible: false,
                    reason: `${participants[j].name} is excluded by too many people and cannot receive a gift`
                };
            }
        }

        // Try to find a valid assignment using backtracking
        const assignment = new Array(n).fill(-1);
        const receiverUsed = new Array(n).fill(false);

        if (this._backtrack(0, assignment, receiverUsed, canGiftTo, n)) {
            return { possible: true, reason: 'Valid assignment exists' };
        }

        return {
            possible: false,
            reason: 'The combination of exclusions makes it impossible to find a valid assignment. Some participants need to remove exclusions.'
        };
    },

    /**
     * Backtracking helper to check if assignment exists
     */
    _backtrack(giverIdx, assignment, receiverUsed, canGiftTo, n) {
        if (giverIdx === n) {
            return true; // All assigned successfully
        }

        // Get valid receivers for this giver, shuffle for randomness check
        const validReceivers = [];
        for (let j = 0; j < n; j++) {
            if (canGiftTo[giverIdx][j] && !receiverUsed[j]) {
                validReceivers.push(j);
            }
        }

        for (const receiverIdx of validReceivers) {
            assignment[giverIdx] = receiverIdx;
            receiverUsed[receiverIdx] = true;

            if (this._backtrack(giverIdx + 1, assignment, receiverUsed, canGiftTo, n)) {
                return true;
            }

            assignment[giverIdx] = -1;
            receiverUsed[receiverIdx] = false;
        }

        return false;
    },

    /**
     * Generate random assignment respecting exclusions
     * Uses most-constrained-first heuristic for better success rate
     * @param {Array} participants - Array of participant objects
     * @returns {Array} Array of { participantId, giverName, assignedTo } or null if impossible
     */
    generateAssignment(participants) {
        const names = participants.map(p => p.name);
        const n = names.length;

        // Build constraint matrix
        const canGiftTo = [];
        const constraintCount = []; // How many people each person can gift to

        for (let i = 0; i < n; i++) {
            canGiftTo[i] = [];
            const giver = participants[i];
            const excluded = new Set(giver.exclusions || []);
            let count = 0;

            for (let j = 0; j < n; j++) {
                const receiver = participants[j];
                canGiftTo[i][j] = (i !== j) && !excluded.has(receiver.name);
                if (canGiftTo[i][j]) count++;
            }
            constraintCount[i] = count;
        }

        // Order givers by most constrained first (fewest options)
        const giverOrder = [...Array(n).keys()].sort((a, b) => constraintCount[a] - constraintCount[b]);

        // Try multiple times with randomization
        for (let attempt = 0; attempt < 100; attempt++) {
            const assignment = new Array(n).fill(-1);
            const receiverUsed = new Array(n).fill(false);

            if (this._assignWithRandomness(0, giverOrder, assignment, receiverUsed, canGiftTo, n)) {
                // Convert to result format
                return participants.map((p, i) => ({
                    participantId: p.id,
                    giverName: p.name,
                    assignedTo: names[assignment[i]]
                }));
            }
        }

        return null; // Failed after all attempts
    },

    /**
     * Recursive assignment with randomization
     */
    _assignWithRandomness(orderIdx, giverOrder, assignment, receiverUsed, canGiftTo, n) {
        if (orderIdx === n) {
            return true;
        }

        const giverIdx = giverOrder[orderIdx];

        // Get valid receivers and shuffle them
        const validReceivers = [];
        for (let j = 0; j < n; j++) {
            if (canGiftTo[giverIdx][j] && !receiverUsed[j]) {
                validReceivers.push(j);
            }
        }

        // Shuffle for randomness
        this._shuffle(validReceivers);

        for (const receiverIdx of validReceivers) {
            assignment[giverIdx] = receiverIdx;
            receiverUsed[receiverIdx] = true;

            if (this._assignWithRandomness(orderIdx + 1, giverOrder, assignment, receiverUsed, canGiftTo, n)) {
                return true;
            }

            assignment[giverIdx] = -1;
            receiverUsed[receiverIdx] = false;
        }

        return false;
    },

    /**
     * Fisher-Yates shuffle
     */
    _shuffle(array) {
        for (let i = array.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [array[i], array[j]] = [array[j], array[i]];
        }
        return array;
    },

    /**
     * Get statistics about constraints
     */
    getConstraintStats(participants) {
        const n = participants.length;
        const stats = {
            totalParticipants: n,
            participants: []
        };

        for (const p of participants) {
            const exclusionCount = (p.exclusions || []).length;
            const maxPossible = n - 1; // Can't gift to self
            const availableRecipients = maxPossible - exclusionCount;

            stats.participants.push({
                name: p.name,
                exclusions: exclusionCount,
                availableRecipients,
                constraintLevel: exclusionCount / maxPossible // 0 = no constraints, 1 = max constraints
            });
        }

        // Sort by most constrained
        stats.participants.sort((a, b) => b.constraintLevel - a.constraintLevel);

        return stats;
    }
};

// Export
window.SecretSantaAlgorithm = SecretSantaAlgorithm;
