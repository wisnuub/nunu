/** @type {import('tailwindcss').Config} */
export default {
  content: [
    './index.html',
    './src/**/*.{js,ts,jsx,tsx}',
  ],
  theme: {
    extend: {
      colors: {
        bg: {
          primary: '#0D0F14',
          sidebar: '#0A0C10',
          card: '#141720',
        },
        accent: {
          blue: '#5B6EF5',
          purple: '#8B5CF6',
        },
        success: '#16A34A',
        warning: '#F59E0B',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
      },
      borderRadius: {
        card: '12px',
        'card-lg': '16px',
        btn: '8px',
      },
    },
  },
  plugins: [],
}
