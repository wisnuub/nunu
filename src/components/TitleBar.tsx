const isMac =
  typeof window !== 'undefined' && window.nunu?.platform === 'darwin'

export function TitleBar() {
  const minimize = () => window.nunu?.minimize()
  const maximize = () => window.nunu?.maximize()
  const close = () => window.nunu?.close()

  return (
    <div
      className="drag-region flex items-center justify-between h-10 px-4 bg-[#0A0C10] shrink-0 z-50"
      style={{ minHeight: 40 }}
    >
      {/* Mac: traffic lights on the left */}
      {isMac ? (
        <div className="no-drag flex items-center gap-2">
          <button
            onClick={close}
            className="w-3 h-3 rounded-full bg-[#FF5F57] hover:brightness-110 transition-all focus:outline-none"
            aria-label="Close"
          />
          <button
            onClick={minimize}
            className="w-3 h-3 rounded-full bg-[#FFBD2E] hover:brightness-110 transition-all focus:outline-none"
            aria-label="Minimize"
          />
          <button
            onClick={maximize}
            className="w-3 h-3 rounded-full bg-[#28C840] hover:brightness-110 transition-all focus:outline-none"
            aria-label="Maximize"
          />
        </div>
      ) : (
        <div className="w-20" />
      )}

      {/* Centered app name */}
      <span className="gradient-text text-sm font-semibold tracking-widest uppercase select-none">
        nunu
      </span>

      {/* Windows: controls on the right */}
      {!isMac ? (
        <div className="no-drag flex items-center">
          <button
            onClick={minimize}
            className="w-10 h-10 flex items-center justify-center text-gray-400 hover:text-white hover:bg-white/10 transition-colors focus:outline-none"
            aria-label="Minimize"
          >
            <svg width="10" height="1" viewBox="0 0 10 1" fill="currentColor">
              <rect width="10" height="1" />
            </svg>
          </button>
          <button
            onClick={maximize}
            className="w-10 h-10 flex items-center justify-center text-gray-400 hover:text-white hover:bg-white/10 transition-colors focus:outline-none"
            aria-label="Maximize"
          >
            <svg width="10" height="10" viewBox="0 0 10 10" fill="none" stroke="currentColor" strokeWidth="1">
              <rect x="0.5" y="0.5" width="9" height="9" />
            </svg>
          </button>
          <button
            onClick={close}
            className="w-10 h-10 flex items-center justify-center text-gray-400 hover:text-white hover:bg-red-600 transition-colors focus:outline-none"
            aria-label="Close"
          >
            <svg width="10" height="10" viewBox="0 0 10 10" fill="none" stroke="currentColor" strokeWidth="1.5">
              <line x1="0" y1="0" x2="10" y2="10" />
              <line x1="10" y1="0" x2="0" y2="10" />
            </svg>
          </button>
        </div>
      ) : (
        <div className="w-20" />
      )}
    </div>
  )
}
