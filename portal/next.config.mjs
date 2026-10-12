/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  output: 'standalone',
  // Allow large downloads and smooth streaming
  experimental: {},
  // Headers for Range requests and download attachment names if needed
  async headers() {
    return [
      {
        source: '/downloads/:path*',
        headers: [
          { key: 'Accept-Ranges', value: 'bytes' },
          { key: 'Cache-Control', value: 'public, max-age=31536000, immutable' }
        ]
      }
    ];
  }
};

export default nextConfig;
