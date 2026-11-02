export const themeStorageKey = "mubangumi-theme";

// Runs in <head> before first paint so a saved choice never flashes the
// other theme. Without a saved choice the page follows the system setting.
export const themeInitScript = `try{var t=localStorage.getItem("${themeStorageKey}");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t}catch(e){}`;
