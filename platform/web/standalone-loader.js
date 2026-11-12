/* Asset bridge for the generated standalone HTML. Never changes global fetch. */
const WarmaEmbedded = (() => {
  const pending = new Map();
  const worklets = new Map();
  function bytes(node) {
    const binary = atob(node.textContent.trim());
    const data = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) data[i] = binary.charCodeAt(i);
    node.remove();
    return data;
  }
  return {
    releaseLoadedData() {
      // Engine has copied the PCK and compiled WASM; discard cached input blobs.
      pending.clear();
    },
    response(name) {
      // Only known built-in assets are accepted; no URL/file-system/network access.
      if (!['index.wasm', 'index.pck'].includes(name)) {
        return Promise.reject(new Error('未知内置资源：' + name));
      }
      if (!pending.has(name)) {
        pending.set(name, (async () => {
          const node = document.getElementById('embedded-' + name);
          if (!node) throw new Error('HTML 内置资源不完整：' + name);
          const mime = node.dataset.mime;
          const expectedSize = Number(node.dataset.size);
          const stream = new Blob([bytes(node)]).stream().pipeThrough(new DecompressionStream('gzip'));
          const data = await new Response(stream).arrayBuffer();
          if (data.byteLength !== expectedSize) throw new Error('HTML 内置资源大小不正确：' + name);
          return new Blob([data], { type: mime });
        })());
      }
      return pending.get(name).then(blob => new Response(blob, { headers: { 'Content-Type': blob.type } }));
    },
    workletURL(name) {
      if (!['index.audio.worklet.js', 'index.audio.position.worklet.js'].includes(name)) {
        throw new Error('未知音频组件：' + name);
      }
      if (!worklets.has(name)) {
        const node = document.getElementById('embedded-' + name);
        if (!node) throw new Error('HTML 音频组件不完整：' + name);
        // data: modules work from opaque file: origins as well as HTTPS. Blob
        // worklet URLs can be rejected by Chromium's file-origin module loader.
        worklets.set(name, 'data:text/javascript;base64,' + node.textContent.trim());
        node.remove();
      }
      return worklets.get(name);
    }
  };
})();
