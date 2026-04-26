window.ACP = Object.assign(window.ACP || {}, {
    activeSessionId: '',
    targetPath: '',
    currentHashId: '',
    isCompareToLatest: false,

    updateSessionList: (data) => {
        const sessions = typeof data === 'string' ? JSON.parse(data) : data;
        const container = document.getElementById('sessionListContainer');

        container.innerHTML = sessions.map(s => `
            <div onclick="window.ACP.selectSession('${s.id}')"
                class="flex items-center gap-3 px-3 py-2.5 rounded-lg cursor-pointer group relative overflow-hidden ${s.id === window.ACP.activeSessionId ? 'bg-surface-container-high border-l-[3px] border-primary' : 'hover:bg-surface-container-high/50 text-on-surface-variant hover:text-on-surface border-l-[3px] border-transparent'}">
                <div class="relative z-10">
                    <div class="w-9 h-9 rounded-full bg-surface-container flex items-center justify-center border border-outline-variant/20">
                        <span class="material-icons text-lg ${s.id === window.ACP.activeSessionId ? 'text-primary' : ''}">${s.id === window.ACP.activeSessionId ? 'forum' : 'chat_bubble_outline'}</span>
                    </div>
                    <div class="absolute -bottom-0.5 -right-0.5 w-3 h-3 ${s.online ? 'bg-primary' : 'bg-gray-400'} rounded-full border-2 border-surface-container-lowest"></div>
                </div>
                <div class="flex-1 min-w-0 z-10">
                    <div class="text-sm font-headline ${s.id === window.ACP.activeSessionId ? 'font-semibold text-primary' : 'font-medium'} truncate">${s.name}</div>
                    <div class="text-xs ${s.id === window.ACP.activeSessionId ? 'text-on-surface-variant' : 'opacity-60'} truncate">${s.workspace || ''}</div>
                </div>
            </div>`).join('');
    },

    selectSession: (sessionId) => {
        window.ACP.activeSessionId = sessionId;
        window.ACP.currentHashId = '';
        window.ACP.isCompareToLatest = false; // Reset mode on session change
        window.ACP.updateToggleUI();
        window.sendDiff('select-session?id=' + sessionId);
        document.getElementById('emptyState').classList.remove('hidden');
        document.getElementById('btnRollback').classList.add('hidden');
        document.getElementById('diffContent').innerHTML = '';
        document.getElementById('fileName').innerText = 'Compare Changes';
        document.getElementById('filePath').innerText = 'No file selected';
        document.getElementById('addCount').innerText = '+0';
        document.getElementById('removeCount').innerText = '-0';
    },

    setCompareMode: (isLatest) => {
        if (window.ACP.isCompareToLatest === isLatest) return;
        window.ACP.isCompareToLatest = isLatest;
        window.ACP.updateToggleUI();

        // Reload current diff if available
        if (window.ACP.currentHashId && window.ACP.activeSessionId) {
            window.sendDiff(`load-diff?hashId=${window.ACP.currentHashId}&sessionId=${window.ACP.activeSessionId}&compareToLatest=${isLatest}`);
        }
    },

    updateToggleUI: () => {
        const btnSnapshot = document.getElementById('btnModeSnapshot');
        const btnLatest = document.getElementById('btnModeLatest');
        if (!btnSnapshot || !btnLatest) return;

        const baseClass = 'flex items-center gap-1.5 px-3 py-1.5 rounded-md text-[10px] font-bold uppercase tracking-wider transition-all';
        const activeClass = 'bg-surface-container-highest text-primary shadow-sm';
        const inactiveClass = 'text-on-surface-variant/60 hover:text-on-surface hover:bg-surface-container-high';

        if (window.ACP.isCompareToLatest) {
            btnSnapshot.className = `${baseClass} ${inactiveClass}`;
            btnLatest.className = `${baseClass} ${activeClass}`;
        } else {
            btnSnapshot.className = `${baseClass} ${activeClass}`;
            btnLatest.className = `${baseClass} ${inactiveClass}`;
        }
    },

    updateFileHistoryBase64: (base64) => {
        try {
            const binary = window.atob(base64);
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
            const json = new TextDecoder().decode(bytes);
            const history = JSON.parse(json);

            const container = document.getElementById('fileHistoryContainer');
            if (!container) return;

            if (!history || history.length === 0) {
                container.innerHTML = '<div class="p-8 text-center text-xs text-on-surface-variant italic opacity-30">No history available</div>';
                return;
            }

            const grouped = {};
            history.forEach(item => {
                const file = item.path.split(/[\/\\]/).pop();
                if (!grouped[file]) grouped[file] = { path: item.path, entries: [] };
                grouped[file].entries.push(item);
            });

            container.innerHTML = Object.keys(grouped).map(file => {
                const data = grouped[file];
                const lastTime = data.entries[0].timestamp.split(' ')[1];

                // Check if this file should be expanded automatically
                const isTarget = window.ACP.targetPath === data.path;
                const expandClass = isTarget ? '' : 'hidden';
                const chevronIcon = isTarget ? 'expand_more' : 'chevron_right';

                const entriesHtml = data.entries.map((e, idx) => {
                    const time = e.timestamp.split(' ')[1];
                    const isFirst = idx === 0;
                    const colorClass = isFirst ? 'bg-primary' : 'bg-on-surface-variant';
                    return `
                        <div class="relative cursor-pointer hover:bg-white/5 p-1 rounded" onclick="window.sendDiff('load-diff?hashId=${e.id}&sessionId=${window.ACP.activeSessionId}&compareToLatest=' + window.ACP.isCompareToLatest)">
                            <span class="absolute -left-[21px] top-2 w-2 h-2 rounded-full ${colorClass} border-2 border-surface-container-low"></span>
                            <p class="text-xs text-on-surface hover:text-primary transition-colors">Diff: ${e.id || 'Snap'}</p>
                            <p class="text-[10px] text-on-surface-variant font-mono mt-0.5">${time}</p>
                        </div>
                    `;
                }).join('');

                return `
                    <div class="bg-surface-container rounded-xl border border-outline-variant/10 overflow-hidden mb-2">
                        <div onclick="this.nextElementSibling.classList.toggle('hidden'); const icon = this.querySelector('.chevron'); icon.innerText = icon.innerText === 'expand_more' ? 'chevron_right' : 'expand_more';" class="p-3 flex items-start gap-3 cursor-pointer hover:bg-surface-container-high transition-colors">
                            <span class="material-symbols-outlined text-primary mt-0.5 text-[18px]">description</span>
                            <div class="flex-1 min-w-0">
                                <p class="text-sm font-medium ${isTarget ? 'text-primary' : 'text-on-surface'} truncate" title="${data.path}">${file}</p>
                                <p class="text-xs text-on-surface-variant mt-0.5">Last Modified ${lastTime}</p>
                            </div>
                            <span class="material-symbols-outlined text-on-surface-variant text-[16px] chevron">${chevronIcon}</span>
                        </div>
                        <div class="${expandClass} px-4 pb-3 pt-1 border-t border-outline-variant/5 bg-surface-container-low/50">
                            <div class="relative pl-4 mt-2 space-y-3 before:absolute before:inset-y-0 before:left-[7px] before:w-px before:bg-outline-variant/20">
                                ${entriesHtml}
                            </div>
                        </div>
                    </div>
                `;
            }).join('');

            // If a target path was requested, load its latest diff automatically
            if (window.ACP.targetPath) {
                const targetFileGroup = grouped[window.ACP.targetPath.split(/[\/\\]/).pop()];
                if (targetFileGroup && targetFileGroup.entries.length > 0) {
                    window.sendDiff(`load-diff?hashId=${targetFileGroup.entries[0].id}&sessionId=${window.ACP.activeSessionId}`);
                    window.ACP.targetPath = ''; // Clear after auto-loading
                }
            }

        } catch (e) { console.error('File History render error:', e); }
    },

    loadDiffFromData: (filename, path, oldText, newText, hashId) => {
        window.ACP.currentHashId = hashId;
        document.getElementById('emptyState').classList.add('hidden');
        document.getElementById('fileName').innerText = filename;
        document.getElementById('filePath').innerText = path;

        const btnRollback = document.getElementById('btnRollback');
        const btnRollbackText = document.getElementById('btnRollbackText');
        if (btnRollback && btnRollbackText) {
            btnRollback.classList.remove('hidden');
            btnRollbackText.innerText = `Rollback to #${hashId}`;
        }

        const container = document.getElementById('diffContent');
        container.innerHTML = '';

        let adds = 0;
        let removes = 0;

        // Use jsdiff to compute line differences
        const diffBlocks = window.Diff.diffLines(oldText || '', newText || '');
        let oldLineNum = 1;
        let newLineNum = 1;

        diffBlocks.forEach((part, blockIdx) => {
            const lines = part.value.replace(/\n$/, '').split('\n');
            const isChanged = part.added || part.removed;

            lines.forEach((line, lineIdx) => {
                const rowEl = document.createElement('div');

                let type = 'unchanged';
                let oldNum = '';
                let newNum = '';

                if (part.added) {
                    type = 'added';
                    newNum = newLineNum++;
                    adds++;
                } else if (part.removed) {
                    type = 'removed';
                    oldNum = oldLineNum++;
                    removes++;
                } else {
                    oldNum = oldLineNum++;
                    newNum = newLineNum++;
                }

                rowEl.className = `diff-row ${type === 'added' ? 'diff-added' : type === 'removed' ? 'diff-removed' : ''}`;
                const escapedContent = window.ACP.escapeHtml(line);

                // Add restore icon only once per block at the first line of the block
                let actionHtml = '';
                if (isChanged && lineIdx === 0) {
                    actionHtml = `<span class="material-symbols-outlined text-[16px] text-on-surface-variant/40 hover:text-primary cursor-pointer transition-colors" title="Rollback this block" onclick="window.ACP.rollbackPartialDiff(${blockIdx})">restore</span>`;
                }

                rowEl.innerHTML = `
                    <div class="diff-num">${oldNum}</div>
                    <div class="diff-content">${type === 'added' ? '' : escapedContent}</div>
                    <div class="diff-action">${actionHtml}</div>
                    <div class="diff-num">${newNum}</div>
                    <div class="diff-content">${type === 'removed' ? '' : escapedContent}</div>
                `;
                container.appendChild(rowEl);
            });
        });

        document.getElementById('addCount').innerText = `+${adds}`;
        document.getElementById('removeCount').innerText = `-${removes}`;
    },

    rollbackCurrentDiff: () => {
        if (!window.ACP.currentHashId || !window.ACP.activeSessionId) return;
        window.ACP.showConfirm(
            'warning',
            'Rollback File',
            `Are you sure you want to rollback this file to state #${window.ACP.currentHashId}?`,
            () => {
                window.sendDiff(`rollback-file?hashId=${window.ACP.currentHashId}&sessionId=${window.ACP.activeSessionId}`);
            }
        );
    },

    rollbackPartialDiff: (blockIdx) => {
        if (!window.ACP.currentHashId || !window.ACP.activeSessionId) return;
        window.sendDiff(`partial-rollback?hashId=${window.ACP.currentHashId}&sessionId=${window.ACP.activeSessionId}&blockIndex=${blockIdx}`); 
    }
});

window.addEventListener('DOMContentLoaded', () => {
    window.sendDiff('diff-action://ready');
});
