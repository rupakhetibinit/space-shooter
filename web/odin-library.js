// Declare Odin runtime imports to Emscripten so unexpected missing symbols
// remain build errors. The shell also supplies the odin_env import namespace.
mergeInto(LibraryManager.library, {
  browser_store: function(ptr, size) { return campaignStore(memory.loadString(ptr,size)); },
  browser_export: function(ptr, size) { campaignDownload(memory.loadString(ptr,size)); },
  browser_pick: function() { document.getElementById('campaign-file').click(); },
  sin: function(x) { return Math.sin(x); },
  cos: function(x) { return Math.cos(x); },
  rand_bytes: function(ptr, len) { odinImports.odin_env.rand_bytes(ptr, len); },
  write: function(fd, ptr, len) { odinImports.odin_env.write(fd, ptr, len); }
});
