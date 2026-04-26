const Explorer = {
    currentPath: '', currentView: 'grid', currentData: [], historyStack: [], forwardStack: [], sortKey: 'name', sortOrder: 'asc', selectedPath: null, searchQuery: '', isInternalNav: false,
    updateFileList(json) {
        const data = typeof json === 'string' ? JSON.parse(json) : json;
        this.currentData = (data.files || []).map(f => ({ ...f, selected: false }));
        const newPath = data.currentPath || (this.currentData.length > 0 ? this.currentData[0].path.split(/[\\\/]/).slice(0,-1).join('\\') : '');
        if (newPath && newPath !== this.currentPath) {
            if (this.isInternalNav) { this.isInternalNav = false; } 
            else { if (this.currentPath) { this.historyStack.push(this.currentPath); this.forwardStack = []; } }
            this.currentPath = newPath;
        }
        this.updateUI(); this.render();
    },
    updateUI() {
        document.getElementById('current-path-display').innerText = this.currentPath || 'Project Root';
        document.getElementById('main-title').innerText = this.currentPath ? this.currentPath.split(/[\\\/]/).pop() : 'Project Root';
        document.getElementById('btn-back').disabled = this.historyStack.length === 0;
        document.getElementById('btn-forward').disabled = this.forwardStack.length === 0;
    },
    goBack() { if (this.historyStack.length === 0) return; this.isInternalNav = true; this.forwardStack.push(this.currentPath); this.navigateTo(this.historyStack.pop()); },
    goForward() { if (this.forwardStack.length === 0) return; this.isInternalNav = true; this.forwardStack.push(this.currentPath); this.navigateTo(this.forwardStack.pop()); },
    goUp() { if (!this.currentPath) return; const parent = this.currentPath.split(/[\\\/]/).slice(0, -1).join('\\'); if (parent) this.navigateTo(parent); },
    navigateTo(path) { window.sendExplorer(`open?path=${encodeURIComponent(path)}&isDir=true`); },
    switchView(view) {
        this.currentView = view;
        document.getElementById('explorer-grid-view').classList.toggle('hidden', view !== 'grid');
        document.getElementById('explorer-list-view').classList.toggle('hidden', view !== 'list');
        document.getElementById('view-toggle-grid').className = view === 'grid' ? 'p-2 rounded bg-surface-variant text-on-surface shadow-md' : 'p-2 rounded text-on-surface-variant hover:text-on-surface transition-colors';
        document.getElementById('view-toggle-list').className = view === 'list' ? 'p-2 rounded bg-surface-variant text-on-surface shadow-md' : 'p-2 rounded text-on-surface-variant hover:text-on-surface transition-colors';
    },
    search(query) { this.searchQuery = query.toLowerCase(); this.render(); },
    render() {
        const gridContainer = document.getElementById('explorer-grid-view'); const listBody = document.getElementById('explorer-list-body');
        gridContainer.innerHTML = ''; listBody.innerHTML = '';
        const filtered = this.currentData.filter(f => f.name.toLowerCase().includes(this.searchQuery));
        filtered.sort((a, b) => { if (a.isDir !== b.isDir) return a.isDir ? -1 : 1; return this.sortOrder === 'asc' ? a.name.localeCompare(b.name) : b.name.localeCompare(a.name); })
        .forEach(item => {
            const isSel = item.path === this.selectedPath;
            const gItem = document.createElement('div');
            gItem.className = `group flex flex-col items-center gap-3 p-3 rounded-xl transition-colors cursor-pointer ${isSel ? 'bg-surface-container-high ring-1 ring-primary/40' : 'hover:bg-surface-container-high'}`;
            gItem.onclick = (e) => Explorer.onItemClick(item, e); gItem.ondblclick = () => Explorer.onItemDoubleClick(item);
            gItem.innerHTML = `<div class="w-16 h-16 bg-surface-container-highest rounded-lg flex items-center justify-center shadow-lg border border-outline-variant/10 group-hover:-translate-y-1 transition-all"><span class="material-symbols-outlined text-4xl ${item.isDir ? 'text-primary' : 'text-tertiary-fixed-dim'}" style="font-variation-settings: 'FILL' 1;">${item.isDir ? 'folder' : 'description'}</span></div><span class="text-xs font-medium text-center truncate w-full">${item.name}</span>`;
            gridContainer.appendChild(gItem);
            const row = document.createElement('tr');
            row.className = `hover:bg-surface-container-highest transition-colors cursor-pointer ${isSel ? 'bg-surface-container-highest border-l-4 border-primary' : 'border-l-4 border-transparent'}`;
            row.onclick = (e) => Explorer.onItemClick(item, e); row.ondblclick = () => Explorer.onItemDoubleClick(item);
            row.innerHTML = `<td class="px-6 py-3 text-center"><input type="checkbox" class="rounded border-outline-variant/30 bg-surface-container-lowest text-primary"/></td><td class="px-6 py-3"><div class="flex items-center gap-3"><span class="material-symbols-outlined ${item.isDir ? 'text-primary' : 'text-secondary'}" style="font-variation-settings: 'FILL' 1;">${item.isDir ? 'folder' : 'description'}</span><span>${item.name}</span></div></td><td class="px-6 py-3 text-xs opacity-60">${item.date}</td><td class="px-6 py-3 text-xs opacity-60">${item.type}</td><td class="px-6 py-3 text-right text-xs opacity-60">${item.size || '--'}</td>`;
            listBody.appendChild(row);
        });
        document.getElementById('status-bar-info').innerText = `${filtered.length} items`;
    },
    onItemClick(item, e) {
        Explorer.selectedPath = item.path; Explorer.render();
        if (!item.isDir) {
            document.getElementById('explorer-main').classList.add('split');
            document.getElementById('preview-pane').classList.add('active');
            document.getElementById('preview-filename').innerText = item.name;
            window.sendExplorer(`get-preview?path=${encodeURIComponent(item.path)}`);
        } else { Explorer.closePreview(); }
    },
    onItemDoubleClick(item) {
        if (item.isDir) { Explorer.navigateTo(item.path); } 
        else { window.sendExplorer(`view-external?path=${encodeURIComponent(item.path)}`); }
    },
    setPreviewContent(content, ext) {
        const codeEl = document.getElementById('preview-code-element');
        const langMap = { 'pas': 'pascal', 'ts': 'typescript', 'json': 'json', 'js': 'javascript' };
        codeEl.className = `language-${langMap[ext] || 'clike'}`; codeEl.textContent = content; Prism.highlightElement(codeEl);
    },
    closePreview() { document.getElementById('explorer-main').classList.remove('split'); document.getElementById('preview-pane').classList.remove('active'); Explorer.selectedPath = null; Explorer.render(); },
    toggleSidebar() { document.getElementById('sidebar').classList.toggle('collapsed'); },
    refresh() { window.sendExplorer(`refresh`); },
    sortBy(key) { if (Explorer.sortKey === key) Explorer.sortOrder = Explorer.sortOrder === 'asc' ? 'desc' : 'asc'; else { Explorer.sortKey = key; Explorer.sortOrder = 'asc'; } Explorer.render(); },
    toggleAll(checked) { /* Logic for bulk selection */ }
};

window.ACP_EXPLORER = Explorer;

window.addEventListener('mousedown', (e) => {
    if (e.button === 3) { e.preventDefault(); window.ACP_EXPLORER.goBack(); }
    else if (e.button === 4) { e.preventDefault(); window.ACP_EXPLORER.goForward(); }
});

// Global Link Guard: Intercepts all <a> clicks (including Ctrl+Click and local file links)
document.addEventListener('click', (e) => {
    const link = e.target.closest('a');
    if (!link || !link.href || link.href.startsWith('javascript:') || (link.getAttribute('href') && link.getAttribute('href').startsWith('#'))) return;

    e.preventDefault();
    e.stopPropagation();
    window.location.href = link.href;
}, true);

window.addEventListener('DOMContentLoaded', () => {
    window.sendExplorer('ready');
});
