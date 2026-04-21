window.sendAcp = function (url) {
    const finalUrl = url.includes('://') ? url : 'acp-action://' + url;
    let iframe = document.getElementById('acp-comm-frame');
    if (!iframe) {
        iframe = document.createElement('iframe');
        iframe.id = 'acp-comm-frame';
        iframe.style.display = 'none';
        document.body.appendChild(iframe);
    }
    iframe.src = finalUrl + (finalUrl.includes('?') ? '&' : '?') + 't=' + Date.now();
};

window.sendUi = function (url) {
    const finalUrl = url.includes('://') ? url : 'ui-action://' + url;
    window.sendAcp(finalUrl);
};

window.ACP = {
    lastAiMsgId: '',
    lastAiThoughtId: null,
    lastBlockType: '',
    lastMessageRole: '',
    activeSessionId: '',
    selectedSearchSessionId: '',
    availableCommands: [],
    workspaceFiles: [],
    selectedCommandIndex: 0,
    selectedFileIndex: 0,
    filteredCommands: [],
    filteredFiles: [],
    thoughtStartTime: 0,
    accumulatedThought: '',
    isProcessingActive: false,
    lastRenderedDate: null,
    allSessions: [],
    
    // Streaming State
    isThoughtStreaming: false,
    isMessageStreaming: false,
    currentStreamingContainerId: null,

    decodeBase64Utf8: (base64) => {
        try {
            const binary = window.atob(base64);
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
            return new TextDecoder('utf-8').decode(bytes);
        } catch (e) {
            console.error('Base64 decode error:', e);
            return null;
        }
    },

    getLocalTimeString: () => {
        const d = new Date();
        const pad = (n) => n.toString().padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
    },

    renderDateBadge: (timestamp) => {
        if (!timestamp) return;
        const container = document.getElementById('mainChatCanvasInner');
        const datePart = timestamp.split(' ')[0];
        if (window.ACP.lastRenderedDate !== datePart) {
            window.ACP.lastRenderedDate = datePart;
            const todayStr = window.ACP.getLocalTimeString().split(' ')[0];
            const displayDate = (datePart === todayStr) ? "Today" : datePart;

            container.insertAdjacentHTML('beforeend', `
                <div class="flex justify-center my-8 px-4">
                    <span class="px-3 py-1 text-[11px] font-medium tracking-wider text-on-surface-variant uppercase bg-surface-container rounded-full border border-outline-variant/10">
                        ${displayDate}
                    </span>
                </div>
            `);
        }
    },

    toggleSearch: (force) => {
        const sidebar = document.getElementById('searchSidebar');
        const isOpen = force !== undefined ? force : sidebar.classList.contains('hidden');

        if (isOpen) {
            sidebar.classList.remove('hidden');
            window.ACP.selectedSearchSessionId = window.ACP.activeSessionId;
            window.ACP.renderSearchSessionMenu();
            document.getElementById('searchQuery').focus();
        } else {
            sidebar.classList.add('hidden');
        }
    },

    toggleSearchOptionsAccordion: () => {
        const content = document.getElementById('searchOptionsAccordionContent');
        const chevron = document.getElementById('searchOptionsAccordionChevron');
        const isHidden = content.classList.contains('hidden');

        if (isHidden) {
            content.classList.remove('hidden');
            chevron.style.transform = 'rotate(180deg)';
        } else {
            content.classList.add('hidden');
            chevron.style.transform = 'rotate(0deg)';
        }
    },

    toggleSearchSessionOptions: () => {
        const checked = document.getElementById('searchThisSessionOnly').checked;
        document.getElementById('searchSessionDropdownContainer').classList.toggle('hidden', !checked);
        if (!checked) window.ACP.toggleSearchSessionMenu(false);
    },

    toggleSearchSessionMenu: (force) => {
        const menu = document.getElementById('searchSessionMenu');
        const isShow = (force !== undefined) ? force : menu.classList.contains('hidden');
        if (isShow) window.ACP.renderSearchSessionMenu();
        menu.classList.toggle('hidden', !isShow);
    },

    renderSearchSessionMenu: () => {
        const menu = document.getElementById('searchSessionMenu');
        const trigger = document.getElementById('searchSessionTrigger');
        if (!menu || !trigger) return;

        const activeSess = window.ACP.allSessions.find(s => s.id === window.ACP.selectedSearchSessionId) || window.ACP.allSessions[0];
        if (activeSess) {
            trigger.querySelector('span:first-child').innerText = activeSess.name;
            window.ACP.selectedSearchSessionId = activeSess.id;
        }

        menu.innerHTML = window.ACP.allSessions.map(s => `
            <button onclick="window.ACP.selectSearchSession('${s.id}', '${s.name}')"
                class="w-full text-left px-4 py-2.5 text-[11px] hover:bg-surface-container-high transition-colors border-b border-white/5 last:border-0 flex flex-col gap-0.5 first:rounded-t-xl last:rounded-b-xl">
                <span class="${s.id === window.ACP.selectedSearchSessionId ? 'text-primary font-bold' : 'text-on-surface'}">${s.name}</span>
                <span class="text-[9px] text-on-surface-variant/40 truncate font-mono">${s.workspace || 'Root'}</span>
            </button>
        `).join('');
    },

    selectSearchSession: (id, name) => {
        window.ACP.selectedSearchSessionId = id;
        document.getElementById('searchSessionTrigger').querySelector('span:first-child').innerText = name;
        window.ACP.toggleSearchSessionMenu(false);
    },

    executeSearch: () => {
        const query = document.getElementById('searchQuery').value.trim();
        if (!query) return;

        document.getElementById('searchEmptyState').classList.add('hidden');
        document.getElementById('searchLoadingState').classList.remove('hidden');
        document.getElementById('searchResultsList').classList.add('hidden');

        const opts = {
            case: document.getElementById('searchCase').checked,
            regex: document.getElementById('searchRegex').checked,
            active: document.getElementById('searchActive').checked,
            inactive: document.getElementById('searchInactive').checked,
            thought: document.getElementById('searchThought').checked,
            user: document.getElementById('searchUser').checked,
            agent: document.getElementById('searchAgent').checked,
            thisSession: document.getElementById('searchThisSessionOnly').checked,
            targetSessionId: window.ACP.selectedSearchSessionId
        };

        let url = `search-conversations?query=${encodeURIComponent(query)}&case=${opts.case}&regex=${opts.regex}&active=${opts.active}&inactive=${opts.inactive}&thought=${opts.thought}&user=${opts.user}&agent=${opts.agent}`;
        if (opts.thisSession && opts.targetSessionId) url += `&targetSessionId=${opts.targetSessionId}`;

        window.sendUi(url);
    },

    updateSearchResults: (base64) => {
        try {
            const binary = window.atob(base64);
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
            const json = new TextDecoder().decode(bytes);
            const results = JSON.parse(json);

            const list = document.getElementById('searchResultsList');
            const loading = document.getElementById('searchLoadingState');

            loading.classList.add('hidden');
            list.classList.remove('hidden');

            if (results.length === 0) {
                list.innerHTML = '<div class="text-center py-12 opacity-40"><p class="text-sm">No matches found</p></div>';
                return;
            }

            list.innerHTML = results.map(session => `
                <div class="bg-surface-container rounded-xl border border-outline-variant/10 overflow-hidden mb-3 shadow-sm hover:border-outline-variant/30 transition-all">
                    <button onclick="this.nextElementSibling.classList.toggle('hidden'); this.querySelector('.chevron').innerText = this.nextElementSibling.classList.contains('hidden') ? 'expand_more' : 'expand_less';" 
                        class="w-full flex items-center justify-between p-4 text-left hover:bg-surface-container-high transition-colors">
                        <div class="min-w-0">
                            <div class="flex items-center gap-2 mb-1">
                                <span class="text-xs font-bold text-primary truncate">${session.name}</span>
                                <span class="text-[10px] text-on-surface-variant/50">${session.matches.length} results</span>
                            </div>
                            <div class="text-[10px] text-on-surface-variant/40 truncate flex items-center gap-1">
                                <span class="material-icons text-[12px]">folder</span>
                                ${session.workspace}
                            </div>
                        </div>
                        <span class="material-icons chevron text-on-surface-variant/30 transition-transform duration-200">expand_more</span>
                    </button>
                    <div class="hidden border-t border-outline-variant/10 bg-surface/30">
                        ${session.matches.map(match => `
                            <div onclick="window.ACP.goToMatch('${session.sessionId}', '${match.timestamp}')" 
                                class="p-4 hover:bg-surface-container-highest cursor-pointer border-b last:border-b-0 border-outline-variant/5 group transition-colors">
                                <div class="flex items-center justify-between mb-2">
                                    <div class="flex items-center gap-2">
                                        <span class="px-1.5 py-0.5 rounded bg-surface-container-high text-[9px] font-bold uppercase tracking-wider text-on-surface-variant">${match.role}</span>
                                        <span class="text-[10px] text-on-surface-variant/40">${match.timestamp}</span>
                                    </div>
                                    <span class="material-icons text-xs text-primary opacity-0 group-hover:opacity-100 transition-opacity">arrow_forward</span>
                                </div>
                                <div class="text-xs text-on-surface-variant leading-relaxed line-clamp-2 italic font-serif">
                                    ${match.snippet}
                                </div>
                            </div>
                        `).join('')}
                    </div>
                </div>
            `).join('');
        } catch (e) { console.error('Search update error:', e); }
    },

    goToMatch: (sessionId, timestamp) => {
        if (window.ACP.activeSessionId !== sessionId) {
            window.sendAcp(`select-session?id=${sessionId}`);
        }

        const tryScroll = (count) => {
            const searchTs = timestamp.trim();
            const elements = Array.from(document.querySelectorAll('[data-timestamp]'));
            const target = elements.find(el => {
                const elTs = el.getAttribute('data-timestamp').trim();
                return elTs === searchTs || elTs.includes(searchTs) || searchTs.includes(elTs);
            });

            if (target) {
                const container = document.getElementById('mainChatCanvas');
                let highlightTarget = null;

                const thoughtHeader = target.querySelector('[id^="thought-hdr-"]');
                if (thoughtHeader) {
                    highlightTarget = thoughtHeader;
                } else {
                    highlightTarget = target.querySelector('.bg-secondary-container, .bg-surface-container-highest');
                }

                const containerRect = container.getBoundingClientRect();
                const targetRect = target.getBoundingClientRect();
                const relativeTop = targetRect.top - containerRect.top + container.scrollTop;
                const targetScrollTop = relativeTop - (container.clientHeight / 2);

                container.scrollTo({ top: targetScrollTop, behavior: 'smooth' });

                if (highlightTarget) {
                    highlightTarget.classList.remove('focus-highlight');
                    void highlightTarget.offsetWidth;
                    highlightTarget.classList.add('focus-highlight');
                }
            } else if (count < 60) {
                setTimeout(() => tryScroll(count + 1), 100);
            }
        };
        tryScroll(0);
    },

    toggleDropdown: (e, force) => {
        if (e) e.stopPropagation();
        const d = document.getElementById('newChatDropdown');
        if (!d) return;
        const isShow = (force !== undefined) ? force : (d.classList.contains('hidden'));
        if (isShow) {
            d.classList.remove('hidden');
            setTimeout(() => { d.classList.remove('opacity-0', 'invisible'); d.classList.add('opacity-100', 'visible'); }, 10);
        } else {
            d.classList.add('opacity-0', 'invisible'); d.classList.remove('opacity-100', 'visible');
            setTimeout(() => { d.classList.add('hidden'); }, 200);
        }
    },

    toggleHistory: () => {
        const sidebar = document.getElementById('historySidebar');
        if (sidebar) {
            const isHidden = sidebar.classList.contains('hidden');
            if (isHidden) window.sendAcp('get-file-history');
            sidebar.classList.toggle('hidden');
        }
    },

    showProcessing: (show) => {
        let indicator = document.getElementById('processingIndicator');
        window.ACP.isProcessingActive = show;

        if (show) {
            const container = document.getElementById('mainChatCanvasInner');
            if (!indicator) {
                const html = `
                    <div id="processingIndicator" class="flex flex-col items-start gap-1.5 max-w-3xl mr-auto mt-4 mb-8 px-4">
                        <div class="bg-surface-container-highest px-5 py-3.5 rounded-2xl rounded-tl-sm border border-outline-variant/10 flex items-center gap-2 shadow-lg">
                            <div class="w-1.5 h-1.5 rounded-full bg-primary/40 animate-pulse"></div>
                            <div class="w-1.5 h-1.5 rounded-full bg-primary/70 animate-pulse delay-75"></div>
                            <div class="w-1.5 h-1.5 rounded-full bg-primary animate-pulse delay-150"></div>
                        </div>
                    </div>`;
                container.insertAdjacentHTML('beforeend', html);
            } else {
                container.appendChild(indicator);
            }
            const outer = document.getElementById('mainChatCanvas');
            outer.scrollTop = outer.scrollHeight;
        } else if (indicator) {
            indicator.remove();
        }
    },

    sendMessage: async () => {
        const input = document.getElementById('userInput');
        const text = input.innerText.trim();
        if (text) {
            input.innerHTML = '';
            window.ACP.breakGrouping();
            window.ACP.showProcessing(true);
            window.sendAcp('send-message?text=' + encodeURIComponent(text));
        }
    },

    addUserMessage: (base64) => {
        const text = window.ACP.decodeBase64Utf8(base64);
        if (!text) return;
        window.ACP.breakGrouping();
        const id = window.ACP.addMessageToUI('me', '', window.ACP.getLocalTimeString());
        const div = document.getElementById(id);
        if (div) div.innerHTML = window.ACP.renderContent(text);
        const outer = document.getElementById('mainChatCanvas');
        outer.scrollTop = outer.scrollHeight;
    },

    resumeSession: () => {
        window.sendAcp('resume-session?id=' + window.ACP.activeSessionId);
    },

    addMessageToUI: (role, text, timestamp) => {
        const container = document.getElementById('mainChatCanvasInner');

        window.ACP.renderDateBadge(timestamp);

        let time = '';
        if (timestamp) {
            const parts = timestamp.split(' ');
            if (parts.length > 1) time = parts[1].substring(0, 5);
            else if (timestamp.includes('T')) time = timestamp.split('T')[1].substring(0, 5);
            else time = timestamp.substring(0, 5);
        } else {
            const d = new Date();
            time = d.getHours().toString().padStart(2, '0') + ':' + d.getMinutes().toString().padStart(2, '0');
        }

        const id = 'msg-' + Date.now() + Math.random().toString(36).substr(2, 5);

        let html = role === 'me' ? `
            <div id="wrapper-${id}" data-timestamp="${timestamp}" class="flex flex-col items-end gap-1.5 max-w-3xl ml-auto mb-8 px-4 transition-all">
                <div class="bg-secondary-container text-on-surface px-5 py-3.5 rounded-2xl rounded-tr-sm shadow-xl shadow-black/20 border border-white/5">
                    <div id="${id}" class="markdown-body text-sm leading-relaxed"></div>
                </div>
                <div class="flex items-center gap-2 mr-1">
                    <span class="text-[11px] text-on-surface-variant font-medium">${time}</span>
                    <span class="material-symbols-outlined text-[14px] text-on-surface-variant">check_circle</span>
                </div>
            </div>` : `
            <div id="wrapper-${id}" data-timestamp="${timestamp}" class="flex flex-col items-start gap-1.5 max-w-3xl mr-auto group mb-8 px-4 transition-all">
                <div class="flex items-center gap-3 mb-1 ml-1 transition-opacity">
                    <span class="text-[11px] font-headline font-semibold text-primary">Gemini-CLI</span>
                    <span class="text-[11px] text-on-surface-variant font-medium">${time}</span>
                </div>
                <div class="bg-surface-container-highest text-on-surface px-5 py-4 rounded-2xl rounded-tl-sm shadow-xl shadow-black/20 border border-outline-variant/10 w-full relative">
                    <div id="${id}" class="markdown-body min-h-[1.5rem]"></div>
                    <div id="${id}-actions" class="mt-4 pt-4 border-t border-outline-variant/10 hidden flex-wrap gap-2"></div>
                </div>
            </div>`;
        container.insertAdjacentHTML('beforeend', html);
        if (window.ACP.isProcessingActive) window.ACP.showProcessing(true);
        const outer = document.getElementById('mainChatCanvas');
        outer.scrollTop = outer.scrollHeight;
        return id;
    },

    createThoughtContainer: (timestamp) => {
        const container = document.getElementById('mainChatCanvasInner');
        const id = 'thought-' + Date.now();
        const hdrId = 'thought-hdr-' + Date.now();
        const actualTimestamp = timestamp || window.ACP.getLocalTimeString();
        window.ACP.thoughtStartTime = Date.now();

        window.ACP.renderDateBadge(actualTimestamp);

        const html = `
            <div class="flex flex-col justify-start mb-4 px-4" data-timestamp="${actualTimestamp}">
                <div class="w-full max-w-3xl flex flex-col space-y-2">
                    <div id="${hdrId}" class="flex items-center space-x-2 text-xs text-gray-500 dark:text-text-muted cursor-pointer hover:text-gray-700 dark:hover:text-gray-300 transition-colors select-none w-max group py-1.5 px-3 rounded-lg border border-transparent transition-all">
                        <span class="material-icons text-sm text-primary">psychology</span>
                        <span class="font-medium">Thinking...</span>
                        <span class="material-icons text-sm">expand_more</span>
                    </div>
                    <div id="${id}" class="pl-5 border-l border-gray-200 dark:border-border-dark ml-2 space-y-2 hidden transition-all">
                    </div>
                </div>
            </div>`;
        container.insertAdjacentHTML('beforeend', html);
        if (window.ACP.isProcessingActive) window.ACP.showProcessing(true);
        const outer = document.getElementById('mainChatCanvas');
        outer.scrollTop = outer.scrollHeight;
        return { contentId: id, headerId: hdrId };
    },

    parseAndRenderThought: (text, containerId) => {
        const div = document.getElementById(containerId);
        if (!div) return;
        const parts = text.split(/\*\*([^*]+)\*\*/g);
        let html = '';
        if (parts[0] && parts[0].trim()) {
            html += `<div class="text-[11px] text-gray-500 dark:text-text-muted/60 mb-2 italic px-1">${marked.parseInline(parts[0])}</div>`;
        }
        for (let i = 1; i < parts.length; i += 2) {
            const subject = parts[i].trim();
            const content = parts[i + 1] ? parts[i + 1].trim() : '';
            html += `
                <div class="flex flex-col space-y-1 mb-2.5 last:mb-0">
                    <div class="flex items-center space-x-2 text-xs text-gray-500 dark:text-text-muted">
                        <span class="material-icons text-[14px]">check</span>
                        <span class="font-medium">${subject}</span>
                    </div>
                    ${content ? `<div class="pl-5 text-[11px] text-gray-500/70 dark:text-text-muted/60 leading-relaxed markdown-body !bg-transparent !p-0 !m-0 border-none shadow-none opacity-80">${marked.parse(content)}</div>` : ''}
                </div>`;
        }
        div.innerHTML = html;
    },

    finalizeThought: () => {
        if (window.ACP.lastAiThoughtId) {
            const hdr = document.getElementById(window.ACP.lastAiThoughtId.headerId);
            const cnt = document.getElementById(window.ACP.lastAiThoughtId.contentId);
            if (hdr) {
                const duration = Math.round((Date.now() - window.ACP.thoughtStartTime) / 1000);
                hdr.classList.remove('py-1.5');
                hdr.classList.add('py-2');
                hdr.querySelector('.material-icons').classList.remove('text-primary');
                hdr.querySelector('.material-icons').classList.add('text-gray-400', 'dark:text-gray-500');
                hdr.querySelector('.font-medium').innerText = `Thought Process (${duration}s)`;
                const arrow = hdr.querySelector('.material-icons:last-child');
                if (arrow) arrow.innerText = 'expand_more';
                if (cnt) cnt.classList.add('hidden');
                hdr.onclick = () => {
                    const isHidden = cnt.classList.contains('hidden');
                    cnt.classList.toggle('hidden');
                    if (arrow) arrow.innerText = isHidden ? 'expand_less' : 'expand_more';
                };
            }
        }
    },

    toggleSessionMenu: (e, sessionId) => {
        if (e) { e.stopPropagation(); e.preventDefault(); }
        const menus = document.querySelectorAll('[id^="session-menu-"]');
        menus.forEach(m => { if (m.id !== `session-menu-${sessionId}`) m.classList.add('hidden'); });

        const menu = document.getElementById(`session-menu-${sessionId}`);
        if (menu) menu.classList.toggle('hidden');
    },

    AddSession: (data) => {
        let s = (typeof data === 'string') ? JSON.parse(window.ACP.decodeBase64Utf8(data)) : data;
        if (!s) return;
        
        const idx = window.ACP.allSessions.findIndex(item => item.id === s.id);
        if (idx === -1) {
            window.ACP.allSessions.push(s);
        } else {
            window.ACP.allSessions[idx] = s;
        }
        window.ACP.updateSessionList(window.ACP.allSessions);
    },

    DeleteSession: (sessionId) => {
        window.ACP.allSessions = window.ACP.allSessions.filter(s => s.id !== sessionId);
        const item = document.getElementById(`session-item-${sessionId}`);
        if (item) item.remove();
        
        if (window.ACP.activeSessionId === sessionId) {
            window.ACP.activeSessionId = '';
            window.ACP.updateActiveSessionUI(null);
        }
    },

    updateSession: (data) => {
        let s = (typeof data === 'string') ? JSON.parse(window.ACP.decodeBase64Utf8(data)) : data;
        if (!s) return;

        const idx = window.ACP.allSessions.findIndex(item => item.id === s.id);
        if (idx === -1) {
            console.error('updateSession: Session ID not found. Use AddSession for new items.', s.id);
            return;
        }

        window.ACP.allSessions[idx] = s;
        const oldActiveId = window.ACP.activeSessionId;

        if (s.active && oldActiveId && oldActiveId !== s.id) {
            const prevIdx = window.ACP.allSessions.findIndex(item => item.id === oldActiveId);
            if (prevIdx !== -1) {
                window.ACP.allSessions[prevIdx].active = false;
                const prevItem = document.getElementById(`session-item-${oldActiveId}`);
                if (prevItem) {
                    const temp = document.createElement('div');
                    temp.innerHTML = window.ACP.renderSessionItemHtml(window.ACP.allSessions[prevIdx]);
                    if (temp.firstElementChild) prevItem.replaceWith(temp.firstElementChild);
                }
            }
        }

        const oldItem = document.getElementById(`session-item-${s.id}`);
        if (oldItem) {
            const temp = document.createElement('div');
            temp.innerHTML = window.ACP.renderSessionItemHtml(s);
            if (temp.firstElementChild) oldItem.replaceWith(temp.firstElementChild);
        }

        if (s.active) {
            window.ACP.updateActiveSessionUI(s);
        }
    },

    // --- Unified Streaming Lifecycle ---
    startStreaming: (type) => {
        window.ACP.breakGrouping(); // Ensure clean state
        if (type === 'thought') {
            window.ACP.isThoughtStreaming = true;
            window.ACP.lastAiThoughtId = window.ACP.createThoughtContainer();
            window.ACP.lastBlockType = 'thought';
            window.ACP.currentStreamingContainerId = window.ACP.lastAiThoughtId.contentId;
            const div = document.getElementById(window.ACP.currentStreamingContainerId);
            if (div) div.classList.remove('hidden');
        } else {
            window.ACP.isMessageStreaming = true;
            window.ACP.lastAiMsgId = window.ACP.addMessageToUI('ai', '', window.ACP.getLocalTimeString());
            window.ACP.lastBlockType = 'message';
            window.ACP.lastMessageRole = 'ai';
            window.ACP.currentStreamingContainerId = window.ACP.lastAiMsgId;
        }
    },

    endStreaming: (type) => {
        if (type === 'thought') {
            window.ACP.isThoughtStreaming = false;
            window.ACP.finalizeThought();
        } else {
            window.ACP.isMessageStreaming = false;
        }
        window.ACP.currentStreamingContainerId = null;
        window.ACP.breakGrouping();
    },

    receiveMessage: (base64) => {
        const content = window.ACP.decodeBase64Utf8(base64);
        if (content === null || !window.ACP.currentStreamingContainerId) return;

        const targetDiv = document.getElementById(window.ACP.currentStreamingContainerId);
        if (targetDiv) {
            if (window.ACP.isThoughtStreaming) {
                window.ACP.parseAndRenderThought(content, window.ACP.currentStreamingContainerId);
            } else {
                targetDiv.innerHTML = window.ACP.renderContent(content);
            }
        }
        
        const outer = document.getElementById('mainChatCanvas');
        outer.scrollTop = outer.scrollHeight;
    },

    streamThought: (data) => {
        // Compatibility wrapper
        if (!window.ACP.isThoughtStreaming) window.ACP.startStreaming('thought');
        window.ACP.receiveMessage(window.btoa(unescape(encodeURIComponent(data.content))));
    },

    renderContent: (content) => {
        let rendered = content;
        rendered = rendered.replace(/(@(?:"[^"]+"|[^\s\xa0\n]+))/g, (match) => {
            let rawPath = match.substring(1).replace(/(^"|"$)/g, '');
            let displayPath = rawPath;
            let fullPath = rawPath;
            if (rawPath.startsWith('file:///')) {
                fullPath = decodeURIComponent(rawPath.substring(8));
                let lastSlash = Math.max(fullPath.lastIndexOf('/'), fullPath.lastIndexOf('\\'));
                displayPath = fullPath.substring(lastSlash + 1);
            }
            let safeFullPath = encodeURIComponent(fullPath);
            return `<span class="text-primary font-medium px-1.5 py-0.5 bg-primary/10 hover:bg-primary/20 cursor-pointer rounded mx-0.5 transition-colors" contenteditable="false" onclick="if(event.detail===1){window.sendUi('open-file-viewer?path=' + '${safeFullPath}')}else if(event.detail===2){window.sendUi('open-diff-viewer?sessionId=' + window.ACP.activeSessionId + '&path=' + '${safeFullPath}')}">@${displayPath}</span>`;
        });
        return window.marked ? marked.parse(rendered) : rendered;
    },

    streamMessage: (data) => {
        // Compatibility wrapper
        const { content, role, stopReason, timestamp } = data;
        if (!window.ACP.isMessageStreaming) window.ACP.startStreaming('message');
        window.ACP.receiveMessage(window.btoa(unescape(encodeURIComponent(content))));
        if (stopReason) window.ACP.endStreaming('message');
    },

    ShowPermissionUI: (base64) => {
        try {
            const json = window.ACP.decodeBase64Utf8(base64);
            const parsed = JSON.parse(json);
            const { id, toolCall, options } = parsed;
            const actionContainerId = `${window.ACP.lastAiMsgId}-actions`;
            const container = document.getElementById(actionContainerId);
            if (!container) return;

            const isOther = toolCall.kind === 'other';
            
            container.classList.remove('hidden');
            container.className = isOther 
                ? `mt-4 pt-4 border-t border-outline-variant/10 grid grid-cols-2 md:grid-cols-4 gap-2`
                : `mt-4 pt-4 border-t border-outline-variant/10 flex flex-wrap gap-2`;

            const displayOptions = options || [
                { optionId: 'proceed_once', name: 'Allow', kind: 'allow_once' }, 
                { optionId: 'cancel', name: 'Reject', kind: 'reject_once' }
            ];

            container.innerHTML = displayOptions.map(opt => {
                let icon = 'check', color = 'text-primary';
                if (opt.kind === 'allow_always' || opt.optionId.includes('always')) icon = 'done_all';
                if (opt.kind === 'reject_once' || opt.optionId === 'cancel') { icon = 'close'; color = 'text-error'; }
                
                return `
                    <button onclick="window.sendAcp('permission-response?id=${id}&optionId=${opt.optionId}'); this.parentElement.classList.add('opacity-50', 'pointer-events-none')"
                        class="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-surface-container-low hover:bg-surface-container border border-outline-variant/20 text-[11px] font-semibold text-on-surface transition-all shadow-sm active:scale-95 group">
                        ${isOther ? '' : `<span class="material-symbols-outlined text-[14px] ${color}">${icon}</span>`}
                        <span class="truncate">${opt.name}</span>
                    </button>`;
            }).join('');

            if (window.ACP.isProcessingActive) window.ACP.showProcessing(true);
            const outer = document.getElementById('mainChatCanvas');
            outer.scrollTop = outer.scrollHeight;
        } catch (e) { console.error('ShowPermissionUI error:', e); }
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
                const entriesHtml = data.entries.map((e, idx) => {
                    const time = e.timestamp.split(' ')[1];
                    const isFirst = idx === 0;
                    const colorClass = isFirst ? 'bg-primary' : 'bg-on-surface-variant';
                    const safePath = encodeURIComponent(e.path);
                    return `
                        <div class="relative cursor-pointer hover:bg-white/5 p-1 rounded" onclick="window.sendUi('open-diff-viewer?sessionId=' + window.ACP.activeSessionId + '&path=${safePath}&hashId=${e.id}')">
                            <span class="absolute -left-[21px] top-2 w-2 h-2 rounded-full ${colorClass} border-2 border-surface-container-low"></span>
                            <p class="text-xs text-on-surface hover:text-primary transition-colors">Diff: ${e.id || 'Snap'}</p>
                            <p class="text-[10px] text-on-surface-variant font-mono mt-0.5">${time}</p>
                        </div>`;
                }).join('');
                const safeDataPath = encodeURIComponent(data.path);
                return `
                    <div class="bg-surface-container rounded-xl border border-outline-variant/10 overflow-hidden mb-2 select-none">
                        <div onclick="this.nextElementSibling.classList.toggle('hidden'); const icon = this.querySelector('.chevron'); icon.innerText = icon.innerText === 'expand_more' ? 'chevron_right' : 'expand_more';" 
                             ondblclick="window.sendUi('open-file-viewer?path=${safeDataPath}')"
                             class="p-3 flex items-start gap-3 cursor-pointer hover:bg-surface-container-high transition-colors">
                            <span class="material-symbols-outlined text-primary mt-0.5 text-[18px]">description</span>
                            <div class="flex-1 min-w-0">
                                <p class="text-sm font-medium text-on-surface truncate" title="${data.path}">${file}</p>
                                <p class="text-xs text-on-surface-variant mt-0.5">Last Modified ${lastTime}</p>
                            </div>
                            <span class="material-symbols-outlined text-on-surface-variant text-[16px] chevron">chevron_right</span>
                        </div>
                        <div class="hidden px-4 pb-3 pt-1 border-t border-outline-variant/5 bg-surface-container-low/50">
                            <div class="relative pl-4 mt-2 space-y-3 before:absolute before:inset-y-0 before:left-[7px] before:w-px before:bg-outline-variant/20">
                                ${entriesHtml}
                            </div>
                        </div>
                    </div>`;
            }).join('');
        } catch (e) { console.error('File History render error:', e); }
    },

    loadHistoryBase64: (base64) => {
        try {
            const binary = window.atob(base64);
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
            const json = new TextDecoder().decode(bytes);
            const data = JSON.parse(json);

            const outer = document.getElementById('mainChatCanvas');
            const wasSmooth = outer.classList.contains('scroll-smooth');
            if (wasSmooth) outer.classList.remove('scroll-smooth');

            document.getElementById('mainChatCanvasInner').innerHTML = '';
            window.ACP.breakGrouping();

            data.forEach(msg => {
                const r = msg.role;
                const targetRole = r === 'user' ? 'me' : 'ai';
                if (r === 'thought') {
                    const tIds = window.ACP.createThoughtContainer(msg.timestamp);
                    window.ACP.parseAndRenderThought(msg.content, tIds.contentId);
                    window.ACP.lastAiThoughtId = tIds;
                    window.ACP.lastBlockType = 'thought';
                    window.ACP.finalizeThought();
                } else {
                    const id = window.ACP.addMessageToUI(targetRole, '', msg.timestamp);
                    const div = document.getElementById(id);
                    if (div) div.innerHTML = window.ACP.renderContent(msg.content);
                }
                window.ACP.breakGrouping();
            });

            setTimeout(() => {
                outer.scrollTop = outer.scrollHeight;
                if (wasSmooth) outer.classList.add('scroll-smooth');
            }, 50);

        } catch (e) { console.error('History load error:', e); }
    },

    clearChat: () => {
        document.getElementById('mainChatCanvasInner').innerHTML = '';
        window.ACP.breakGrouping();
        window.ACP.lastRenderedDate = null;
        window.ACP.showProcessing(false);
    },

    breakGrouping: () => {
        if (window.ACP.lastBlockType === 'thought') window.ACP.finalizeThought();
        window.ACP.lastAiMsgId = '';
        window.ACP.lastAiThoughtId = null;
        window.ACP.lastBlockType = '';
        window.ACP.lastMessageRole = '';
    },

    getTriggerInfo: (triggerChar) => {
        const sel = window.getSelection();
        if (!sel.rangeCount) return null;
        const range = sel.getRangeAt(0);
        const node = range.startContainer;
        if (node.nodeType !== Node.TEXT_NODE) return null;

        const text = node.textContent.substring(0, range.startOffset);
        const lastTriggerIndex = text.lastIndexOf(triggerChar);
        if (lastTriggerIndex === -1) return null;

        const lastWord = text.substring(lastTriggerIndex);
        if (/[\s\xa0\n]/.test(lastWord)) return null;
        if (lastTriggerIndex > 0 && !/[\s\xa0\n]/.test(text[lastTriggerIndex - 1])) return null;

        window.ACP.lastTriggerInfo = {
            node: node,
            triggerChar: triggerChar,
            startIndex: lastTriggerIndex,
            endIndex: range.startOffset
        };

        return lastWord.substring(1).toLowerCase();
    },

    replaceTriggerRange: (triggerChar, replacement) => {
        const info = window.ACP.lastTriggerInfo;
        if (!info || info.triggerChar !== triggerChar) return;

        try {
            const node = info.node;
            if (node.parentNode) {
                const range = document.createRange();
                range.setStart(node, info.startIndex);
                range.setEnd(node, info.endIndex);
                range.deleteContents();
                if (node.textContent.substring(info.startIndex, info.startIndex + (info.endIndex - info.startIndex)) === info.triggerChar + window.ACP.getTriggerInfo(triggerChar)) {
                    node.deleteData(info.startIndex, info.endIndex - info.startIndex);
                }
                const inserted = (typeof replacement === 'string') ? document.createTextNode(replacement) : replacement;
                range.insertNode(inserted);
                range.setStartAfter(inserted);
                const space = document.createTextNode('\u00A0');
                range.insertNode(space);
                range.setStartAfter(space);
                range.collapse(true);
                const sel = window.getSelection();
                sel.removeAllRanges();
                sel.addRange(range);
            }
            document.getElementById('userInput').focus();
        } catch (e) { console.error('Replace error:', e); }
        window.ACP.lastTriggerInfo = null;
    },

    scrollToActive: (containerId) => {
        const container = document.getElementById(containerId);
        if (!container) return;
        const active = container.querySelector('.cmd-item.active');
        if (active) active.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    },

    handleSlashCommand: () => {
        const query = window.ACP.getTriggerInfo('/');
        if (query !== null) {
            const filtered = (window.ACP.availableCommands || []).filter(c => query === "" || c.name.toLowerCase().includes(query));
            if (filtered.length > 0) {
                window.ACP.filteredCommands = filtered; window.ACP.selectedCommandIndex = 0;
                window.ACP.renderCommands(filtered); window.ACP.showCommands(true);
                return;
            }
        }
        window.ACP.showCommands(false);
    },

    handleAtCommand: () => {
        const query = window.ACP.getTriggerInfo('@');
        if (query !== null) {
            const filtered = (window.ACP.workspaceFiles || []).filter(f => query === "" || f.toLowerCase().includes(query)).slice(0, 20);
            if (filtered.length > 0) {
                window.ACP.filteredFiles = filtered; window.ACP.selectedFileIndex = 0;
                window.ACP.renderFiles(filtered); window.ACP.showFiles(true);
                return;
            }
        }
        window.ACP.showFiles(false);
    },

    renderCommands: (commands) => {
        const container = document.getElementById('commandListContainer');
        if (!container) return;
        container.innerHTML = '<div class="dropdown-header">COMMANDS</div>' + commands.map((c, i) => `
            <div onmousedown="event.preventDefault(); window.ACP.applyCommand('${c.name}')"
                class="cmd-item w-full flex items-center gap-4 px-5 py-3.5 cursor-pointer transition-colors ${i === window.ACP.selectedCommandIndex ? 'active' : ''}">
                <div class="icon-box w-7 h-7 rounded bg-surface-container flex items-center justify-center transition-colors"><span class="material-icons text-sm">terminal</span></div>
                <div class="flex-1 min-w-0">
                    <div class="text-sm font-bold font-mono text-highlight">/${c.name}</div>
                    ${c.description ? `<div class="text-[11px] text-on-surface-variant/60 truncate mt-0.5">${c.description}</div>` : ''}
                </div>
            </div>`).join('');
    },

    renderFiles: (files) => {
        const container = document.getElementById('fileListContainer');
        if (!container) return;
        container.innerHTML = '<div class="dropdown-header">WORKSPACE FILES</div>' + files.map((f, i) => `
            <div onmousedown="event.preventDefault(); window.ACP.applyFile('${f}')"
                class="cmd-item w-full flex items-center gap-4 px-5 py-3 cursor-pointer transition-colors ${i === window.ACP.selectedFileIndex ? 'active' : ''}">
                <span class="material-icons text-sm ${i === window.ACP.selectedFileIndex ? 'text-primary' : 'text-on-surface-variant/40'}">description</span>
                <span class="text-xs font-mono truncate text-highlight">${f}</span>
            </div>`).join('');
    },

    showCommands: (show) => { document.getElementById('commandDropdown').classList.toggle('hidden', !show); },
    showFiles: (show) => { document.getElementById('fileDropdown').classList.toggle('hidden', !show); },
    showToolbox: () => {
        const filtered = window.ACP.availableCommands || [];
        window.ACP.filteredCommands = filtered;
        window.ACP.selectedCommandIndex = 0;
        window.ACP.renderCommands(filtered);
        window.ACP.showCommands(true);
        document.getElementById('userInput').focus();
    },
    applyCommand: (name) => {
        const hasTrigger = window.ACP.getTriggerInfo('/') !== null;
        if (hasTrigger) {
            window.ACP.replaceTriggerRange('/', '/' + name);
        } else {
            const selection = window.getSelection();
            if (selection.rangeCount) {
                const range = selection.getRangeAt(0);
                const textNode = document.createTextNode('/' + name);
                range.insertNode(textNode);
                range.setStartAfter(textNode);
                const space = document.createTextNode('\u00A0');
                range.insertNode(space);
                range.setStartAfter(space);
                range.collapse(true);
                selection.removeAllRanges(); selection.addRange(range);
            } else {
                document.getElementById('userInput').innerText += '/' + name + ' ';
            }
        }
        window.ACP.showCommands(false);
    },
    applyFile: (path) => {
        const pill = document.createElement('span');
        let safeFullPath = encodeURIComponent(path);
        pill.className = 'text-primary font-medium px-1.5 py-0.5 bg-primary/10 hover:bg-primary/20 cursor-pointer rounded mx-0.5 transition-colors';
        pill.setAttribute('onclick', `if(window.pillTimer) clearTimeout(window.pillTimer); if(event.detail===1){window.pillTimer=setTimeout(()=>window.sendUi('open-file-viewer?path=' + '${safeFullPath}'), 250);}else if(event.detail===2){window.sendUi('open-diff-viewer?sessionId=' + window.ACP.activeSessionId + '&path=' + '${safeFullPath}')}`);
        pill.contentEditable = 'false';
        const label = path.includes(' ') ? `@"${path}"` : `@${path}`;
        pill.innerText = label;
        window.ACP.replaceTriggerRange('@', pill); window.ACP.showFiles(false);
    }, setWorkspaceFiles: (files) => { window.ACP.workspaceFiles = files; },
    showTyping: (show) => { window.ACP.showProcessing(show); },
    showModal: (type, title, desc) => {
        const overlay = document.getElementById('modalOverlay');
        const container = document.getElementById('modalContainer');
        const icon = document.getElementById('modalIcon');
        const iconBg = document.getElementById('modalIconBg');
        const titleEl = document.getElementById('modalTitle');
        const descEl = document.getElementById('modalDescription');

        const configs = {
            warning: { icon: 'warning', color: 'text-warning', bg: 'bg-warning' },
            info: { icon: 'info', color: 'text-primary', bg: 'bg-primary' },
            question: { icon: 'help', color: 'text-secondary', bg: 'bg-secondary' },
            error: { icon: 'error', color: 'text-error', bg: 'bg-error' }
        };

        const config = configs[type] || configs.info;
        
        icon.className = 'material-symbols-outlined text-5xl relative z-10 ' + config.color;
        iconBg.className = 'absolute inset-0 opacity-10 ' + config.bg;
        
        icon.innerText = config.icon;
        titleEl.innerText = title;
        descEl.innerText = desc;

        overlay.classList.remove('hidden');
        setTimeout(() => {
            overlay.classList.remove('opacity-0');
            container.classList.remove('scale-95');
        }, 10);
    },
    closeModal: () => {
        const overlay = document.getElementById('modalOverlay');
        const container = document.getElementById('modalContainer');
        overlay.classList.add('opacity-0');
        container.classList.add('scale-95');
        setTimeout(() => overlay.classList.add('hidden'), 300);
    },
    showConfirm: (type, title, desc, onConfirm) => {
        const overlay = document.getElementById('confirmOverlay');
        const container = document.getElementById('confirmContainer');
        const icon = document.getElementById('confirmIcon');
        const iconBg = document.getElementById('confirmIconBg');
        const titleEl = document.getElementById('confirmTitle');
        const descEl = document.getElementById('confirmDescription');
        const okBtn = document.getElementById('confirmOkBtn');

        const configs = {
            warning: { icon: 'warning', color: 'text-warning', bg: 'bg-warning' },
            info: { icon: 'info', color: 'text-primary', bg: 'bg-primary' },
            question: { icon: 'help', color: 'text-secondary', bg: 'bg-secondary' },
            error: { icon: 'error', color: 'text-error', bg: 'bg-error' }
        };

        const config = configs[type] || configs.question;
        
        icon.className = 'material-symbols-outlined text-5xl relative z-10 ' + config.color;
        iconBg.className = 'absolute inset-0 opacity-10 ' + config.bg;
        
        icon.innerText = config.icon;
        titleEl.innerText = title;
        descEl.innerText = desc;

        okBtn.onclick = () => {
            if (onConfirm) onConfirm();
            window.ACP.closeConfirm();
        };

        overlay.classList.remove('hidden');
        setTimeout(() => {
            overlay.classList.remove('opacity-0');
            container.classList.remove('scale-95');
        }, 10);
    },
    closeConfirm: () => {
        const overlay = document.getElementById('confirmOverlay');
        const container = document.getElementById('confirmContainer');
        overlay.classList.add('opacity-0');
        container.classList.add('scale-95');
        setTimeout(() => overlay.classList.add('hidden'), 300);
    },
    parseStructuredPrompt: async (text) => { return text; }
};

// --- Core ACP UI Handlers ---
window.ACP.updateActiveSessionUI = (activeSession) => {
    if (!activeSession) {
        window.ACP.activeSessionId = '';
        const header = document.getElementById('activeAgentHeader');
        if (header) header.innerText = 'No Session';
        const inputArea = document.getElementById('mainInputArea');
        if (inputArea) inputArea.classList.add('hidden');
        const chatCanvas = document.getElementById('mainChatCanvas');
        if (chatCanvas) chatCanvas.classList.add('hidden');
        const emptyArea = document.getElementById('mainEmptyArea');
        if (emptyArea) emptyArea.classList.remove('hidden');
        const canvas = document.getElementById('mainChatCanvasInner');
        if (canvas) canvas.innerHTML = '';
        return;
    }

    if (window.ACP.activeSessionId !== activeSession.id) {
        window.ACP.activeSessionId = activeSession.id;
        const canvas = document.getElementById('mainChatCanvasInner');
        if (canvas) canvas.innerHTML = '';
    }

    const header = document.getElementById('activeAgentHeader');
    if (header) header.innerText = activeSession.name;

    const inputArea = document.getElementById('mainInputArea');
    if (inputArea) inputArea.classList.remove('hidden');

    const chatCanvas = document.getElementById('mainChatCanvas');
    if (chatCanvas) chatCanvas.classList.remove('hidden');

    const emptyArea = document.getElementById('mainEmptyArea');
    if (emptyArea) emptyArea.classList.add('hidden');

    if (activeSession.commands) window.ACP.availableCommands = activeSession.commands;

    const isActive = activeSession.isActive;
    const isWaitForResponse = activeSession.isWaitForResponse;
    const isLoading = activeSession.loading;
    
    const setDisabled = (val) => {
        const modelSelectBtn = document.getElementById('modelSelectBtn');
        const attachBtn = document.getElementById('attachBtn');
        const toolsBtn = document.getElementById('toolsBtn');
        if (modelSelectBtn) modelSelectBtn.disabled = val;
        if (attachBtn) attachBtn.disabled = val;
        if (toolsBtn) toolsBtn.disabled = val;
    };

    const sendBtn = document.getElementById('send-button');
    const userInput = document.getElementById('userInput');

    if (sendBtn && userInput) {
        if (isLoading || !isActive) {
            sendBtn.innerHTML = `<span class="material-symbols-outlined text-[20px] ${isLoading ? 'animate-spin' : ''}">${isLoading ? 'refresh' : 'autorenew'}</span>`;
            sendBtn.onclick = isLoading ? null : () => window.ACP.resumeSession();
            userInput.setAttribute('contenteditable', 'false');
            setDisabled(true);
            sendBtn.disabled = false;
        } else {
            sendBtn.innerHTML = `<span class="material-symbols-outlined text-[20px]">send</span>`;
            sendBtn.onclick = () => window.ACP.sendMessage();
            userInput.setAttribute('contenteditable', 'true');
            setDisabled(false);
            sendBtn.disabled = isWaitForResponse;
        }
    }

    if (activeSession.models && document.getElementById('modelSelectBtn')) {
        const currentModelId = activeSession.models.currentModelId || '';
        let currentModelLabel = currentModelId;
        const dropdown = document.getElementById('modelDropdown');
        if (dropdown && Array.isArray(activeSession.models.availableModels)) {
            dropdown.innerHTML = '<div class="dropdown-header">AVAILABLE MODELS</div>';
            activeSession.models.availableModels.forEach(m => {
                const mId = typeof m === 'string' ? m : m.modelId;
                const mName = typeof m === 'string' ? m : (m.name || m.modelId);
                const mDesc = typeof m === 'object' ? m.description : '';
                const isActiveModel = mId === currentModelId;
                if (isActiveModel) currentModelLabel = mName;
                dropdown.innerHTML += `
                    <button onclick="window.sendAcp('change-model?modelId=${mId}'); document.getElementById('modelDropdown').classList.add('hidden');"
                        class="cmd-item w-full text-left px-5 py-3 transition-colors flex items-center justify-between">
                        <div class="flex flex-col min-w-0">
                            <span class="text-sm font-bold ${isActiveModel ? 'text-primary' : 'text-on-surface'}">${mName}</span>
                            ${mDesc ? `<span class="text-[10px] text-on-surface-variant/60 truncate mt-0.5">${mDesc}</span>` : ''}
                        </div>
                        ${isActiveModel ? '<span class="material-icons text-primary text-sm">check</span>' : ''}
                    </button>`;
            });
        }
        const labelSpan = document.getElementById('modelSelectBtn').querySelector('span:nth-child(2)');
        if (labelSpan) {
            labelSpan.innerText = currentModelLabel || 'Select Model';
            labelSpan.className = 'text-on-surface font-medium';
        }
    }
};

window.ACP.updateSessionList = (data) => {
    let sessions = null;
    if (Array.isArray(data)) {
        sessions = data;
    } else if (typeof data === 'string') {
        const json = window.ACP.decodeBase64Utf8(data);
        if (json) {
            try { sessions = JSON.parse(json); } catch (e) { console.error('updateSessionList JSON parse error:', e); }
        }
    }

    if (!sessions) return;
    window.ACP.allSessions = sessions;

    const container = document.getElementById('sessionListContainer');
    if (!container) return;

    window.ACP.updateActiveSessionUI(sessions.find(s => s.active));
    container.innerHTML = sessions.map(s => window.ACP.renderSessionItemHtml(s)).join('') + '<div class="h-32"></div>';
};

window.ACP.renderSessionItemHtml = (s) => {
    if (!s) return '';
    return `
        <div id="session-item-${s.id}" onclick="window.sendAcp('select-session?id=${s.id}')" 
            class="flex items-center gap-3 px-3 py-2.5 rounded-lg cursor-pointer group relative overflow-visible ${s.active ? 'bg-surface-container-high border-l-[3px] border-primary' : 'hover:bg-surface-container-high/50 text-on-surface-variant hover:text-on-surface border-l-[3px] border-transparent'}">
            <div class="relative z-10 shrink-0">
                <div class="w-9 h-9 rounded-full bg-surface-container flex items-center justify-center border border-outline-variant/20">
                    <span class="material-icons text block ${s.active ? 'text-primary' : ''}">${s.active ? 'forum' : 'chat_bubble_outline'}</span>
                </div>
                <div class="absolute -bottom-0.5 -right-0.5 w-3 h-3 ${s.online ? 'bg-primary' : 'bg-gray-400'} rounded-full border-2 border-surface-container-lowest"></div>
            </div>
            <div class="flex-1 min-w-0 z-10 pr-2">
                <div class="text-sm font-headline ${s.active ? 'font-semibold text-primary' : 'font-medium'} truncate flex items-center gap-1.5">
                    <span class="truncate name-label">${s.name || 'Untitled'}</span>
                    ${s.pinned ? '<span class="material-symbols-outlined text-[12px] text-primary shrink-0">push_pin</span>' : ''}
                </div>
                <div class="text-xs workspace-label ${s.active ? 'text-on-surface-variant' : 'opacity-60'} truncate">${s.workspace || ''}</div>
                ${(s.lastConversationDate && s.lastConversationDate > 0) ? `<div class="text-[9px] text-on-surface-variant/40 mt-0.5">Last active: ${new Date(s.lastConversationDate).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</div>` : ''}
            </div>
            
            <div class="relative z-20 shrink-0">
                <button onclick="window.ACP.toggleSessionMenu(event, '${s.id}')" 
                    class="w-8 h-8 flex items-center justify-center rounded-lg hover:bg-surface-container-highest transition-all opacity-0 group-hover:opacity-100 focus:opacity-100">
                    <span class="material-icons text-[20px] leading-none">more_vert</span>
                </button>
                <div id="session-menu-${s.id}" class="hidden absolute right-0 top-full mt-1 w-52 bg-surface-container-highest border border-outline-variant/20 rounded-xl shadow-2xl z-[100] py-1.5 overflow-hidden">
                    <button onclick="event.stopPropagation(); window.sendAcp('pin-session?id=${s.id}');" class="w-full flex items-center px-4 py-2.5 text-xs text-on-surface hover:bg-surface-container-high transition-colors text-left">
                        <div class="w-8 shrink-0 flex items-center justify-start"><span class="material-symbols-outlined text-[18px]">push_pin</span></div>
                        <span class="flex-1">${s.pinned ? 'Unpin Session' : 'Pin Session'}</span>
                    </button>
                    <button onclick="event.stopPropagation(); window.sendUi('open-explorer?path=' + encodeURIComponent('${(s.workspace || '').replace(/\\/g, '\\\\')}'));" class="w-full flex items-center px-4 py-2.5 text-xs text-on-surface hover:bg-surface-container-high transition-colors text-left">
                        <div class="w-8 shrink-0 flex items-center justify-start"><span class="material-symbols-outlined text-[18px]">folder</span></div>
                        <span class="flex-1">Open Explorer</span>
                    </button>
                    <button onclick="event.stopPropagation(); window.sendUi('open-diff-viewer?sessionId=${s.id}');" class="w-full flex items-center px-4 py-2.5 text-xs text-on-surface hover:bg-surface-container-high transition-colors text-left">
                        <div class="w-8 shrink-0 flex items-center justify-start"><span class="material-symbols-outlined text-[18px]">text_compare</span></div>
                        <span class="flex-1">Open Diff Viewer</span>
                    </button>
                    <div class="h-px bg-outline-variant/10 my-1 mx-2"></div>
                    <button onclick="event.stopPropagation(); window.ACP.showConfirm('error', 'Delete Session', 'Are you sure you want to delete this session? All conversation history will be permanently removed.', () => window.sendAcp('delete-session?id=${s.id}'));" class="w-full flex items-center px-4 py-2.5 text-xs text-error hover:bg-error/10 transition-colors text-left">
                        <div class="w-8 shrink-0 flex items-center justify-start"><span class="material-symbols-outlined text-[18px] text-error">delete</span></div>
                        <span class="flex-1">Delete Session</span>
                    </button>
                </div>
            </div>
        </div>`;
};