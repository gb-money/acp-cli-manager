const Viewer = {
    loadFile: (filename, path, content) => {
        document.getElementById('emptyState').classList.add('hidden');
        document.getElementById('fileName').innerText = filename;
        document.getElementById('filePath').innerText = path;
        const ext = filename.split('.').pop().toLowerCase();
        if (ext === 'md') { Viewer.showMarkdown(content); } 
        else { Viewer.showCode(content, ext); }
    },
    showCode: (content, ext) => {
        const cv = document.getElementById('codeViewer'); const mv = document.getElementById('markdownViewer'); const codeEl = document.getElementById('codeElement'); const codeContainer = document.getElementById('codeContainer');
        cv.classList.remove('hidden'); mv.classList.add('hidden'); document.getElementById('fileIcon').innerText = 'code';
        const langMap = { 'pas': 'pascal', 'dfm': 'pascal', 'fmx': 'pascal', 'dpr': 'pascal', 'ts': 'typescript', 'js': 'javascript', 'html': 'markup', 'css': 'css', 'json': 'json', 'md': 'markdown' };
        const lang = langMap[ext] || 'clike'; codeEl.className = `language-${lang}`; codeEl.textContent = content; codeContainer.classList.add('line-numbers'); Prism.highlightElement(codeEl);
    },
    showMarkdown: (content) => {
        const cv = document.getElementById('codeViewer'); const mv = document.getElementById('markdownViewer'); const mdContent = document.getElementById('markdownContent');
        cv.classList.add('hidden'); mv.classList.remove('hidden'); document.getElementById('fileIcon').innerText = 'article';
        mdContent.innerHTML = marked.parse(content); Prism.highlightAllUnder(mdContent);
    }
};

window.ACP_FILE_VIEWER = Viewer;

// Global Link Guard: Intercepts all <a> clicks (including Ctrl+Click and local file links)
document.addEventListener('click', (e) => {
    const link = e.target.closest('a');
    if (!link || !link.href || link.href.startsWith('javascript:') || (link.getAttribute('href') && link.getAttribute('href').startsWith('#'))) return;

    e.preventDefault();
    e.stopPropagation();
    window.location.href = link.href;
}, true);
