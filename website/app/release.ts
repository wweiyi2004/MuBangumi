const tag = "v2.4.2%2B4032";
const download = "https://github.com/wweiyi2004/MuBangumi/releases/download";

export const currentRelease = {
  version: "2.4.2",
  build: 4032,
  date: "2026-10-01",
  url: `https://github.com/wweiyi2004/MuBangumi/releases/tag/${tag}`,
  assets: {
    android: {
      url: `${download}/${tag}/MuBangumi-2.4.2-build4032-android.apk`,
      file: "MuBangumi-2.4.2-build4032-android.apk",
    },
    windows: {
      url: `${download}/${tag}/MuBangumi-2.4.2-build4032-windows-x64.zip`,
      file: "MuBangumi-2.4.2-build4032-windows-x64.zip",
    },
  },
} as const;
