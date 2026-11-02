const tag = "v2.5.1%2B4035";
const download = "https://github.com/wweiyi2004/MuBangumi/releases/download";

export const currentRelease = {
  version: "2.5.1",
  build: 4035,
  date: "2026-11-02",
  url: `https://github.com/wweiyi2004/MuBangumi/releases/tag/${tag}`,
  assets: {
    android: {
      url: `${download}/${tag}/MuBangumi-2.5.1-build4035-android.apk`,
      file: "MuBangumi-2.5.1-build4035-android.apk",
    },
    windows: {
      url: `${download}/${tag}/MuBangumi-2.5.1-build4035-windows-x64.zip`,
      file: "MuBangumi-2.5.1-build4035-windows-x64.zip",
    },
  },
} as const;
