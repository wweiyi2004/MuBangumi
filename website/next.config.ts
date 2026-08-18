import type { NextConfig } from "next";

const isGitHubPages = process.env.GITHUB_PAGES === "true";
const repositoryBasePath = "/MuBangumi";

const nextConfig: NextConfig = {
  output: isGitHubPages ? "export" : undefined,
  assetPrefix: isGitHubPages ? repositoryBasePath : undefined,
  trailingSlash: isGitHubPages,
  images: {
    unoptimized: isGitHubPages,
  },
};

export default nextConfig;
