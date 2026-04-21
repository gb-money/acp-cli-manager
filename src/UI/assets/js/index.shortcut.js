// --- Shortcut Managers ---
class ACPShortcutManager {
    constructor(acp) { this.acp = acp; }
    init() { window.addEventListener('keydown', (e) => this.handleKeydown(e)); }
    handleKeydown(e) {
        if (e.altKey && (e.key === 'ArrowUp' || e.key === 'ArrowDown')) {
            e.preventDefault();
            this.navigateSession(e.key === 'ArrowUp' ? -1 : 1);
            return;
        }
        if (e.altKey && e.code === 'KeyN') {
            e.preventDefault(); this.acp.toggleDropdown(null); return;
        }
        const dropdown = document.getElementById('newChatDropdown');
        if (dropdown && !dropdown.classList.contains('hidden')) {
            if (e.code === 'KeyG') {
                e.preventDefault(); window.sendAcp('new-chat?agent=gemini'); this.acp.toggleDropdown(null, false);
            }
        }
    }
    navigateSession(dir) {
        window.sendAcp(dir === 1 ? 'next-session' : 'prev-session');
    }
}

class ShortcutManager {
    constructor(acp) { this.acp = acp; }
    init() {
        const input = document.getElementById('userInput');
        if (input) input.addEventListener('keydown', (e) => this.handleInputKeydown(e));
    }
    handleInputKeydown(e) {
        const cd = document.getElementById('commandDropdown');
        const fd = document.getElementById('fileDropdown');
        const isCommandVisible = !cd.classList.contains('hidden');
        const isFileVisible = !fd.classList.contains('hidden');
        if (isCommandVisible || isFileVisible) {
            if (e.key === 'ArrowDown') {
                e.preventDefault(); this._navigate(isCommandVisible, 1);
            } else if (e.key === 'ArrowUp') {
                e.preventDefault(); this._navigate(isCommandVisible, -1);
            } else if (e.key === 'Enter' || e.key === 'Tab') {
                e.preventDefault(); this._confirm(isCommandVisible);
            } else if (e.key === 'Escape') {
                this.acp.showCommands(false); this.acp.showFiles(false);
            }
            return;
        }
        if (e.key === 'Enter' && !e.shiftKey) { 
            e.preventDefault(); 
            const s = this.acp.allSessions.find(sess => sess.active);
            if (s && !s.isWaitForResponse && !s.loading && s.isActive) {
                this.acp.sendMessage(); 
            }
        }
    }
    _navigate(isCommand, dir) {
        if (isCommand) {
            this.acp.selectedCommandIndex = (this.acp.selectedCommandIndex + dir + this.acp.filteredCommands.length) % this.acp.filteredCommands.length;
            this.acp.renderCommands(this.acp.filteredCommands);
            this.acp.scrollToActive('commandListContainer');
        } else {
            this.acp.selectedFileIndex = (this.acp.selectedFileIndex + dir + this.acp.filteredFiles.length) % this.acp.filteredFiles.length;
            this.acp.renderFiles(this.acp.filteredFiles);
            this.acp.scrollToActive('fileListContainer');
        }
    }
    _confirm(isCommand) {
        if (isCommand) this.acp.applyCommand(this.acp.filteredCommands[this.acp.selectedCommandIndex].name);
        else this.acp.applyFile(this.acp.filteredFiles[this.acp.selectedFileIndex]);
    }
}

window.addEventListener('DOMContentLoaded', () => {
    const input = document.getElementById('userInput');
    if (input) {
        input.addEventListener('input', function () {
            window.ACP.handleSlashCommand(this.innerText);
            window.ACP.handleAtCommand(this.innerText);
        });
    }

    // Initialize Shortcut Managers
    window.acpShortcutManager = new ACPShortcutManager(window.ACP);
    window.acpShortcutManager.init();
    window.shortcutManager = new ShortcutManager(window.ACP);
    window.shortcutManager.init();

    document.addEventListener('click', (e) => {
        if (!e.target.closest('[id^="session-menu-"]') && !e.target.closest('button[onclick*="toggleSessionMenu"]')) {
            document.querySelectorAll('[id^="session-menu-"]').forEach(m => m.classList.add('hidden'));
        }
        if (!e.target.closest('#newChatDropdown') && !e.target.closest('button[onclick*="toggleDropdown"]')) {
            const d = document.getElementById('newChatDropdown');
            if (d) { d.classList.add('opacity-0', 'invisible'); setTimeout(() => d.classList.add('hidden'), 200); }
        }
        if (!e.target.closest('#modelDropdown') && !e.target.closest('#modelSelectBtn')) {
            const md = document.getElementById('modelDropdown');
            if (md) md.classList.add('hidden');
        }
        if (!e.target.closest('#searchSessionDropdownContainer')) {
            const ssm = document.getElementById('searchSessionMenu');
            if (ssm) ssm.classList.add('hidden');
        }
        const link = e.target.closest('a');
        if (link && link.href && !link.href.startsWith('javascript:') && !(link.getAttribute('href') && link.getAttribute('href').startsWith('#'))) {
            e.preventDefault(); e.stopPropagation(); window.location.href = link.href;
        }
    }, true);

    window.sendUi('ready');
});