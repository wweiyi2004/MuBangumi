const tag = "v2.5.0%2B4034";
const download = "https://github.com/wweiyi2004/MuBangumi/releases/download";

export const currentRelease = {
  version: "2.5.0",
  build: 4034,
  date: "2026-10-21",
  url: `https://github.com/wweiyi2004/MuBangumi/releases/tag/${tag}`,
  assets: {
    android: {
      url: `${download}/${tag}/MuBangumi-2.5.0-build4034-android.apk`,
      file: "MuBangumi-2.5.0-build4034-android.apk",
    },
    windows: {
      url: `${download}/${tag}/MuBangumi-2.5.0-build4034-windows-x64.zip`,
      file: "MuBangumi-2.5.0-build4034-windows-x64.zip",
    },
  },
} as const;
