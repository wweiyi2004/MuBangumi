import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const title = "MuBangumi — 简单又好看的 Bangumi 客户端";
const description =
  "开源、跨平台的第三方 Bangumi 客户端，把收藏、进度、发现与社区收进一个舒服的应用。";
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ??
  "https://wweiyi2004.github.io/MuBangumi/";
const metadataBase = new URL(siteUrl);

export const dynamic = "force-static";

export const metadata: Metadata = {
  metadataBase,
  title,
  description,
  keywords: ["MuBangumi", "Bangumi", "追番", "Flutter", "开源客户端"],
  alternates: {
    canonical: siteUrl,
  },
  icons: {
    icon: new URL("favicon.svg", metadataBase).toString(),
    shortcut: new URL("favicon.svg", metadataBase).toString(),
  },
  openGraph: {
    title,
    description,
    url: siteUrl,
    type: "website",
    locale: "zh_CN",
    siteName: "MuBangumi",
    images: [
      {
        url: new URL("og.png", metadataBase).toString(),
        width: 1734,
        height: 907,
        alt: "MuBangumi — 追番这件事，简单又好看。",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title,
    description,
    images: [new URL("og.png", metadataBase).toString()],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body className={`${geistSans.variable} ${geistMono.variable}`}>
        {children}
      </body>
    </html>
  );
}
