class AppFont {
  const AppFont({
    required this.id,
    required this.name,
    required this.family,
    required this.description,
    required this.url,
    required this.bytes,
    required this.digest,
    this.gitBlob = false,
    required this.licenseAsset,
    this.imported = false,
  });
  final String id, name, family, description, url, digest, licenseAsset;
  final int bytes;
  final bool gitBlob;
  final bool imported;
}

const downloadableFonts = [
  AppFont(
    id: 'wenkai-1.522',
    name: '霞鹜文楷',
    family: 'MuWenKai1522',
    description: '手写感 · 温柔的阅读风格',
    url:
        'https://github.com/lxgw/LxgwWenKai/releases/download/v1.522/LXGWWenKai-Regular.ttf',
    bytes: 25575676,
    digest: '39ad71264b588165b469e35e6afb162a378dacd1f95348160240ba9038ac3009',
    licenseAsset: 'assets/licenses/LXGWWenKai-OFL.txt',
  ),
  AppFont(
    id: 'noto-sans-sc-9710da1',
    name: 'Noto Sans SC',
    family: 'MuNotoSansSC9710',
    description: '简洁黑体 · 字重丰富',
    url:
        'https://raw.githubusercontent.com/google/fonts/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf',
    bytes: 17772300,
    digest: 'fb0637bafbcd804fe32152370a1225990745b4bc',
    gitBlob: true,
    licenseAsset: 'assets/licenses/NotoSansSC-OFL.txt',
  ),
  AppFont(
    id: 'noto-serif-sc-9710da1',
    name: 'Noto Serif SC',
    family: 'MuNotoSerifSC9710',
    description: '典雅宋体 · 适合长文阅读',
    url:
        'https://raw.githubusercontent.com/google/fonts/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf',
    bytes: 25125512,
    digest: 'eab063faf229160a52d3760f5555150e4eb9e5bf',
    gitBlob: true,
    licenseAsset: 'assets/licenses/notoserifsc-OFL.txt',
  ),
  AppFont(
    id: 'zcool-kuaile-9710da1',
    name: '站酷快乐体',
    family: 'MuZcoolKuaile9710',
    description: '活泼圆润 · 轻松的手写风格',
    url:
        'https://raw.githubusercontent.com/google/fonts/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/zcoolkuaile/ZCOOLKuaiLe-Regular.ttf',
    bytes: 1514968,
    digest: '3cf6cd927ee910d46875de173efdaac4330e84ac',
    gitBlob: true,
    licenseAsset: 'assets/licenses/zcoolkuaile-OFL.txt',
  ),
  AppFont(
    id: 'zcool-xiaowei-9710da1',
    name: '站酷小薇体',
    family: 'MuZcoolXiaowei9710',
    description: '清秀文艺 · 有书卷气的宋体',
    url:
        'https://raw.githubusercontent.com/google/fonts/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/zcoolxiaowei/ZCOOLXiaoWei-Regular.ttf',
    bytes: 6313808,
    digest: '2d8731a231f2e6625b32d96b87f84852e24f9d82',
    gitBlob: true,
    licenseAsset: 'assets/licenses/zcoolxiaowei-OFL.txt',
  ),
];
