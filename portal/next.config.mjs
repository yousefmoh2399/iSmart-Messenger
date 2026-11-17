/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  output: 'standalone',
  compress: false, // Ensures binary installer downloads (.exe / .apk) are not compressed or corrupted by gzip
  experimental: {},
  async rewrites() {
    return [
      {
        source: '/downloads/:path*\\.exe',
        destination: '/api/portal/download?file=windows',
      },
      {
        source: '/downloads/:path*\\.apk',
        destination: '/api/portal/download?file=mobile',
      },
    ];
  },
  async headers() {
    return [
      {
        source: '/downloads/:path*',
        headers: [
          { key: 'Accept-Ranges', value: 'bytes' },
          { key: 'Cache-Control', value: 'no-store, no-cache, must-revalidate' }
        ]
      }
    ];
  }
};

export default nextConfig;
