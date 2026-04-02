import { useState } from 'react'
import { useAppStore } from '../../store/appStore'

type NavItem = {
  id: 'home' | 'my-games' | 'discover' | 'settings'
  label: string
  icon: React.ReactNode
}

function HomeIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="3" width="7" height="7" rx="1" />
      <rect x="14" y="3" width="7" height="7" rx="1" />
      <rect x="3" y="14" width="7" height="7" rx="1" />
      <rect x="14" y="14" width="7" height="7" rx="1" />
    </svg>
  )
}

function GamepadIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="7" width="20" height="11" rx="5" />
      <path d="M7 12h4M9 10v4" />
      <circle cx="16" cy="12" r=".5" fill="currentColor" />
      <circle cx="18" cy="10" r=".5" fill="currentColor" />
    </svg>
  )
}

function CompassIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="9" />
      <path d="M16.24 7.76l-3.18 6.36-6.36 3.18 3.18-6.36 6.36-3.18z" />
    </svg>
  )
}

function GearIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="3" />
      <path d="M12 2v2M12 20v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M2 12h2M20 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42" />
    </svg>
  )
}

const NAV_ITEMS: NavItem[] = [
  { id: 'home', label: 'Home', icon: <HomeIcon /> },
  { id: 'my-games', label: 'My Games', icon: <GamepadIcon /> },
  { id: 'discover', label: 'Discover', icon: <CompassIcon /> },
  { id: 'settings', label: 'Settings', icon: <GearIcon /> },
]

export function Sidebar() {
  const { activeView, setActiveView, hasUpdate, isSignedIn, userEmail } = useAppStore()
  const [expanded, setExpanded] = useState(false)

  return (
    <div
      className="flex flex-col shrink-0 bg-[#0A0C10] border-r border-white/5 transition-all duration-300 overflow-hidden"
      style={{ width: expanded ? 220 : 72 }}
      onMouseEnter={() => setExpanded(true)}
      onMouseLeave={() => setExpanded(false)}
    >
      {/* Logo */}
      <div className="h-16 flex items-center px-4 shrink-0">
        <div
          className="w-10 h-10 rounded-xl flex items-center justify-center shrink-0 text-xl"
          style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}
        >
          🤖
        </div>
        {expanded && (
          <span className="ml-3 text-white font-bold text-lg gradient-text whitespace-nowrap">
            nunu
          </span>
        )}
      </div>

      {/* Nav */}
      <nav className="flex-1 flex flex-col gap-1 px-2 pt-4">
        {NAV_ITEMS.map((item) => {
          const isActive = activeView === item.id
          const showDot = item.id === 'settings' && hasUpdate

          return (
            <button
              key={item.id}
              onClick={() => setActiveView(item.id)}
              className={`relative flex items-center gap-3 px-3 py-3 rounded-[8px] transition-all duration-200 focus:outline-none group ${
                isActive
                  ? 'bg-white/10 text-white'
                  : 'text-white/40 hover:text-white/70 hover:bg-white/5'
              }`}
            >
              {/* Active indicator */}
              {isActive && (
                <div
                  className="absolute left-0 top-1/2 -translate-y-1/2 w-0.5 h-6 rounded-r-full"
                  style={{ background: 'linear-gradient(180deg, #5B6EF5, #8B5CF6)' }}
                />
              )}

              <span className="shrink-0">{item.icon}</span>

              {expanded && (
                <span className="text-sm font-medium whitespace-nowrap">{item.label}</span>
              )}

              {/* Update dot */}
              {showDot && (
                <span
                  className={`absolute ${expanded ? 'right-3' : 'top-2 right-2'} w-2 h-2 rounded-full bg-[#5B6EF5]`}
                />
              )}
            </button>
          )
        })}
      </nav>

      {/* User avatar */}
      {isSignedIn && (
        <div className="px-3 py-4 shrink-0">
          <div className="flex items-center gap-3">
            <div
              className="w-9 h-9 rounded-full flex items-center justify-center text-sm font-bold shrink-0"
              style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}
            >
              {userEmail ? userEmail[0].toUpperCase() : 'U'}
            </div>
            {expanded && (
              <span className="text-xs text-white/50 truncate max-w-[120px]">{userEmail}</span>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
