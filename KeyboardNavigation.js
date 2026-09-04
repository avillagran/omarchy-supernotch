function activePlugin(contentRefs, current) {
  if (!contentRefs || current < 0 || current >= contentRefs.length)
    return null
  return contentRefs[current] || null
}

function isBlocked(plugin) {
  return !!(plugin && plugin.keyboardNavigationBlocked === true)
}

function dispatch(plugin, action, payload) {
  if (!plugin || typeof plugin.handleKeyboardAction !== "function")
    return false
  return plugin.handleKeyboardAction(action, payload || {}) === true
}
