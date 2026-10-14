-- Default settings, option ranges and internal memory limits (spec §5, §10).
local _, ns = ...

local Defaults = {}
ns.Core.Defaults = Defaults

Defaults.SCHEMA_VERSION = 1

-- User-facing option ranges.
Defaults.RANGES = {
  duplicateWindow = { min = 5, max = 120 },
  floodWindow = { min = 3, max = 60 },
  floodMax = { min = 3, max = 30 },
  quarantineMax = { min = 20, max = 500 },
  quarantineTtl = { min = 60, max = 3600 },
}

-- Internal limits: configuration, not performance promises.
Defaults.LIMITS = {
  maxRules = 100,
  maxRuleBytes = 128,
  maxTextBytes = 4096,
  maxIdentityBytes = 96,
  maxAuthorsPerChannel = 500,
  maxChannels = 20,
  maxDuplicateKeys = 5000,
  maxDecisionCache = 2000,
  decisionCacheTtl = 30,
  maxListEntries = 500,
  breakerErrors = 3,
  breakerWindow = 60,
}

Defaults.MODES = { observe = true, filter = true }

function Defaults.NewDB()
  return {
    schemaVersion = Defaults.SCHEMA_VERSION,
    enabled = true,
    mode = "observe",
    channels = {},
    duplicate = { enabled = true, windowSeconds = 30 },
    flood = { enabled = false, windowSeconds = 10, maxMessages = 5 },
    customTerms = { enabled = false, nextId = 1, list = {} },
    allowlist = {},
    blocklist = {},
    quarantine = { maxEntries = 200, ttlSeconds = 900 },
    ui = {},
  }
end
