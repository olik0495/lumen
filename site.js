// Copy the install line.
document.getElementById('copyCmd').addEventListener('click', async e => {
  const text = document.getElementById('installCmd').textContent;
  try { await navigator.clipboard.writeText(text); e.target.textContent = 'Copied!'; }
  catch { const r = document.createRange(); r.selectNodeContents(document.getElementById('installCmd')); getSelection().removeAllRanges(); getSelection().addRange(r); e.target.textContent = 'Press Ctrl+C'; }
  setTimeout(() => { e.target.textContent = 'Copy'; }, 2000);
});
// The download buttons always point at the newest version (asked from GitHub; if that fails they open the
// releases page, where the zips are listed).
(async () => {
  try {
    const r = await fetch('https://api.github.com/repos/olik0495/lumen/releases/latest', { headers: { Accept: 'application/vnd.github+json' } });
    if (!r.ok) return;
    const rel = await r.json();
    const version = String(rel.tag_name || '').replace(/^v/, '');
    const find = re => (rel.assets || []).find(a => re.test(a.name));
    const zips = { browser: find(/^Lumen-Browser-[\d.]+\.zip$/), plain: find(/^Lumen-[\d.]+\.zip$/) };
    // (only a download from Lumen's own releases: never wherever an answer might point)
    const ours = z => z && typeof z.browser_download_url === 'string' && z.browser_download_url.startsWith('https://github.com/olik0495/lumen/releases/download/');
    document.querySelectorAll('[data-dl]').forEach(a => { const z = zips[a.dataset.dl]; if (ours(z)) a.href = z.browser_download_url; });
    if (version) {
      document.getElementById('ver').textContent = 'Version ' + version;
      document.getElementById('footVer').textContent = version;
      document.getElementById('dlLabel').textContent = 'Download Lumen ' + version;
    }
    if (zips.browser) document.getElementById('dlSize').textContent = `${Math.round(zips.browser.size / 1048576)} MB`;
    // What's new: the list at the top of the release notes.
    const notes = String(rel.body || '').split(/\r?\n/).filter(l => /^\s*[-*] /.test(l)).map(l => l.replace(/^\s*[-*] /, '').replace(/\*\*/g, ''));
    if (notes.length) {
      document.getElementById('whatsNewTitle').textContent = `What's new in ${version}`;
      const ul = document.getElementById('whatsNewList');
      notes.slice(0, 6).forEach(n => { const li = document.createElement('li'); li.textContent = n; ul.append(li); });
      document.getElementById('whatsNew').style.display = 'block';
    }
  } catch { /* offline or GitHub busy: the buttons still lead to the downloads */ }
})();
