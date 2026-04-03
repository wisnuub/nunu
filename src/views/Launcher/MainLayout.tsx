import { useEffect } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { useAppStore } from '../../store/appStore'
import { Sidebar } from './Sidebar'
import { GameLibrary } from './GameLibrary'
import { MyGames } from './MyGames'
import { Discover } from './Discover'
import { Settings } from '../Settings/Settings'

const PAGE_TITLES: Record<string, string> = {
  home: 'Home',
  'my-games': 'My Games',
  discover: 'Discover',
  settings: 'Settings',
}

export function MainLayout() {
  const { activeView, hasUpdate, setVmStatus } = useAppStore()

  // Global VM status listener — persists across tab switches
  useEffect(() => {
    return window.nunu?.onVmStatus?.((evt) => {
      if (evt.status === 'booting') setVmStatus('booting')
      else if (evt.status === 'ready') setVmStatus('ready')
      else if (evt.status === 'stopped') setVmStatus('stopped', null)
      else if (evt.status === 'error') setVmStatus('error', null)
    })
  }, [setVmStatus])

  return (
    <div className="flex h-full w-full overflow-hidden">
      <Sidebar />

      {/* Main content */}
      <div className="flex-1 flex flex-col overflow-hidden bg-[#0D0F14]">
        {/* Page header */}
        <div className="flex items-center justify-between px-8 pt-6 pb-2 shrink-0">
          <h1 className="text-xl font-semibold text-white">
            {PAGE_TITLES[activeView]}
          </h1>

          {hasUpdate && activeView !== 'settings' && (
            <div
              className="flex items-center gap-2 px-3 py-1.5 rounded-full text-xs font-medium cursor-pointer"
              style={{
                background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)',
              }}
              onClick={() => useAppStore.getState().setActiveView('settings')}
            >
              <span className="w-1.5 h-1.5 rounded-full bg-white" />
              Update available
            </div>
          )}
        </div>

        {/* Scrollable content */}
        <div className="flex-1 overflow-y-auto px-8 pb-8">
          {activeView === 'home' && <GameLibrary />}
          {activeView === 'my-games' && <MyGames />}
          {activeView === 'discover' && <Discover />}
          {activeView === 'settings' && <Settings />}
        </div>
      </div>
    </div>
  )
}
