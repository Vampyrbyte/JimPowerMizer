-- A service window is open: auction house, mailbox, bank, vendor.
-- The Compat layer tracks the windows and triggers re-evaluation itself.
local _, ns = ...

ns.Engine:RegisterSituation({
	key = "serviceWindow",
	name = "Auction house / mail / bank / vendor",
	Evaluate = function()
		return ns.Compat:IsServiceWindowOpen()
	end,
})
