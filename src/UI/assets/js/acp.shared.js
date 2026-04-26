window.sendAcp = function(url) {
    const finalUrl = (url.indexOf('://') !== -1) ? url : 'acp-action://' + url;
    let iframe = document.getElementById('acp-comm-frame');
    if (!iframe) {
        iframe = document.createElement('iframe'); 
        iframe.id = 'acp-comm-frame';
        iframe.style.display = 'none'; 
        document.body.appendChild(iframe);
    }
    iframe.src = finalUrl + (finalUrl.indexOf('?') !== -1 ? '&' : '?') + 't=' + Date.now();
};

window.sendUi = function(url) {
    const finalUrl = (url.indexOf('://') !== -1) ? url : 'ui-action://' + url;
    window.sendAcp(finalUrl);
};

window.sendDiff = function(url) {
    const finalUrl = (url.indexOf('://') !== -1) ? url : 'diff-action://' + url;
    window.sendAcp(finalUrl);
};

window.sendExplorer = function(url) {
    const finalUrl = (url.indexOf('://') !== -1) ? url : 'explorer-action://' + url;
    window.sendAcp(finalUrl);
};

window.ACP = window.ACP || {};

Object.assign(window.ACP, {
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

    escapeHtml: (unsafe) => {
        return (unsafe || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/\"/g, '&quot;')
            .replace(/'/g, '&#039;');
    },

    showModal: (type, title, desc) => {
        const overlay = document.getElementById('modalOverlay');
        if (!overlay) return;
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
        setTimeout(() => { overlay.classList.remove('opacity-0'); container.classList.remove('scale-95'); }, 10);
    },

    closeModal: () => {
        const overlay = document.getElementById('modalOverlay');
        const container = document.getElementById('modalContainer');
        if (!overlay || !container) return;
        overlay.classList.add('opacity-0');
        container.classList.add('scale-95');
        setTimeout(() => overlay.classList.add('hidden'), 300);
    },

    showConfirm: (type, title, desc, onConfirm) => {
        const overlay = document.getElementById('confirmOverlay');
        if (!overlay) return;
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
        okBtn.onclick = () => { if (onConfirm) onConfirm(); window.ACP.closeConfirm(); };
        overlay.classList.remove('hidden');
        setTimeout(() => { overlay.classList.remove('opacity-0'); container.classList.remove('scale-95'); }, 10);
    },

    closeConfirm: () => {
        const overlay = document.getElementById('confirmOverlay');
        const container = document.getElementById('confirmContainer');
        if (!overlay || !container) return;
        overlay.classList.add('opacity-0');
        container.classList.add('scale-95');
        setTimeout(() => overlay.classList.add('hidden'), 300);
    },

    injectSharedModals: () => {
        if (document.getElementById('modalOverlay')) return;
        const html = `
        <div id="modalOverlay" class="fixed inset-0 z-[200] flex items-center justify-center bg-black/60 backdrop-blur-sm hidden opacity-0 transition-opacity duration-300">
            <div id="modalContainer" class="bg-surface-container-highest border border-outline-variant/20 rounded-[32px] p-8 max-w-[360px] w-full mx-4 shadow-2xl shadow-black/50 transform scale-95 transition-transform duration-300">
                <div class="text-center">
                    <div id="modalIconBox" class="w-20 h-20 rounded-3xl flex items-center justify-center mx-auto mb-6 shadow-inner relative overflow-hidden">
                        <div id="modalIconBg" class="absolute inset-0 opacity-10"></div>
                        <span id="modalIcon" class="material-symbols-outlined text-5xl relative z-10"></span>
                    </div>
                    <h3 id="modalTitle" class="font-headline font-bold text-xl text-on-surface mb-3 tracking-tight"></h3>
                    <p id="modalDescription" class="text-sm text-on-surface-variant leading-relaxed mb-8 px-2"></p>
                    <button onclick="window.ACP.closeModal()" class="w-full py-3.5 px-6 rounded-2xl bg-surface-container-high hover:bg-surface-container-highest text-on-surface font-bold text-sm transition-all active:scale-95 border border-outline-variant/20 shadow-lg">Dismiss</button>
                </div>
            </div>
        </div>
        <div id="confirmOverlay" class="fixed inset-0 z-[210] flex items-center justify-center bg-black/60 backdrop-blur-sm hidden opacity-0 transition-opacity duration-300">
            <div id="confirmContainer" class="bg-surface-container-highest border border-outline-variant/20 rounded-[32px] p-8 max-w-[360px] w-full mx-4 shadow-2xl shadow-black/50 transform scale-95 transition-transform duration-300 text-on-surface">
                <div class="text-center">
                    <div id="confirmIconBox" class="w-20 h-20 rounded-3xl flex items-center justify-center mx-auto mb-6 shadow-inner relative overflow-hidden">
                        <div id="confirmIconBg" class="absolute inset-0 opacity-10"></div>
                        <span id="confirmIcon" class="material-symbols-outlined text-5xl relative z-10"></span>
                    </div>
                    <h3 id="confirmTitle" class="font-headline font-bold text-xl text-on-surface mb-3 tracking-tight"></h3>
                    <p id="confirmDescription" class="text-sm text-on-surface-variant leading-relaxed mb-8 px-2"></p>
                    <div class="flex gap-3">
                        <button onclick="window.ACP.closeConfirm()" class="flex-1 py-3.5 px-4 rounded-2xl bg-surface-container-low hover:bg-surface-container border border-outline-variant/20 text-on-surface font-bold text-sm transition-all active:scale-95">Cancel</button>
                        <button id="confirmOkBtn" class="flex-1 py-3.5 px-4 rounded-2xl bg-primary text-on-primary font-bold text-sm transition-all active:scale-95 shadow-lg shadow-primary/20">Confirm</button>
                    </div>
                </div>
            </div>
        </div>`;
        document.body.insertAdjacentHTML('beforeend', html);
    }
});

window.addEventListener('DOMContentLoaded', () => {
    window.ACP.injectSharedModals();
});
