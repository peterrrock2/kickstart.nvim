-- HTML-style Unicode entity expansion for tokens like ::&rarr::.

local M = {}

M.shortcuts = {
  { token = '->', char = '→' },
  { token = '--', char = '—' },
}

M.entities = {
  -- HTML basics
  amp = '&',
  gt = '>',
  lt = '<',
  nbsp = vim.fn.nr2char(0x00a0),
  quot = '"',

  -- Punctuation and marks
  bdquo = '„',
  bull = '•',
  dagger = '†',
  Dagger = '‡',
  hellip = '…',
  laquo = '«',
  ldquo = '“',
  lsaquo = '‹',
  lsquo = '‘',
  mdash = '—',
  md = '—',
  ndash = '–',
  para = '¶',
  prime = '′',
  Prime = '″',
  raquo = '»',
  rdquo = '”',
  reg = '®',
  rsaquo = '›',
  rsquo = '’',
  sbquo = '‚',
  sect = '§',
  trade = '™',

  -- Currency
  cent = '¢',
  curren = '¤',
  euro = '€',
  pound = '£',
  yen = '¥',

  -- Fractions, superscripts, units
  deg = '°',
  frac12 = '½',
  frac14 = '¼',
  frac34 = '¾',
  micro = 'µ',
  middot = '·',
  permil = '‰',
  sup1 = '¹',
  sup2 = '²',
  sup3 = '³',

  -- Arrows
  dArr = '⇓',
  darr = '↓',
  downarrow = '↓',
  hArr = '⇔',
  harr = '↔',
  leftrightarrow = '↔',
  lArr = '⇐',
  larr = '←',
  leftarrow = '←',
  nearr = '↗',
  nwarr = '↖',
  rArr = '⇒',
  rarr = '→',
  rightarrow = '→',
  searr = '↘',
  swarr = '↙',
  uArr = '⇑',
  uarr = '↑',
  uparrow = '↑',

  -- Math operators and relations
  ['and'] = '∧',
  asymp = '≈',
  cap = '∩',
  cong = '≅',
  cup = '∪',
  divide = '÷',
  empty = '∅',
  equiv = '≡',
  exist = '∃',
  forall = '∀',
  frasl = '⁄',
  ge = '≥',
  infin = '∞',
  int = '∫',
  isin = '∈',
  lang = '⟨',
  le = '≤',
  minus = '−',
  nabla = '∇',
  ne = '≠',
  ni = '∋',
  notin = '∉',
  nsub = '⊄',
  oplus = '⊕',
  ['or'] = '∨',
  otimes = '⊗',
  part = '∂',
  perp = '⊥',
  plusmn = '±',
  prod = '∏',
  prop = '∝',
  radic = '√',
  rang = '⟩',
  sdot = '⋅',
  sim = '∼',
  sub = '⊂',
  sube = '⊆',
  sum = '∑',
  sup = '⊃',
  supe = '⊇',
  there4 = '∴',
  times = '×',

  -- Greek uppercase
  Alpha = 'Α',
  Beta = 'Β',
  Chi = 'Χ',
  Delta = 'Δ',
  Epsilon = 'Ε',
  Eta = 'Η',
  Gamma = 'Γ',
  Iota = 'Ι',
  Kappa = 'Κ',
  Lambda = 'Λ',
  Mu = 'Μ',
  Nu = 'Ν',
  Omega = 'Ω',
  Omicron = 'Ο',
  Phi = 'Φ',
  Pi = 'Π',
  Psi = 'Ψ',
  Rho = 'Ρ',
  Sigma = 'Σ',
  Tau = 'Τ',
  Theta = 'Θ',
  Upsilon = 'Υ',
  Xi = 'Ξ',
  Zeta = 'Ζ',

  -- Greek lowercase
  alpha = 'α',
  beta = 'β',
  chi = 'χ',
  delta = 'δ',
  epsilon = 'ε',
  eta = 'η',
  gamma = 'γ',
  iota = 'ι',
  kappa = 'κ',
  lambda = 'λ',
  mu = 'μ',
  nu = 'ν',
  omega = 'ω',
  omicron = 'ο',
  phi = 'φ',
  pi = 'π',
  psi = 'ψ',
  rho = 'ρ',
  sigma = 'σ',
  sigmaf = 'ς',
  tau = 'τ',
  theta = 'θ',
  upsilon = 'υ',
  xi = 'ξ',
  zeta = 'ζ',

  -- Misc symbols
  check = '✓',
  checkmark = '✓',
  clubs = '♣',
  cross = '✗',
  diams = '♦',
  hearts = '♥',
  loz = '◊',
  spades = '♠',
  star = '☆',
  starf = '★',
}

local function token_before_cursor(line, col)
  local left = line:sub(1, col)

  for _, shortcut in ipairs(M.shortcuts) do
    local token = shortcut.token
    if left:sub(-#token) == token then
      return {
        start_col = col - #token,
        end_col = col,
        char = shortcut.char,
      }
    end
  end

  local start, name = left:match '()::&([%w][%w%d]*);?::$'
  if not start then
    return nil
  end
  return {
    start_col = start - 1,
    end_col = col,
    name = name,
  }
end

function M.expand_at_cursor()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local token = token_before_cursor(line, col)
  if not token then
    return false
  end

  local char = token.char or M.entities[token.name]
  if not char then
    return false
  end

  local new_line = line:sub(1, token.start_col) .. char .. line:sub(token.end_col + 1)
  vim.api.nvim_set_current_line(new_line)
  vim.api.nvim_win_set_cursor(0, { row, token.start_col + #char })
  return true
end

function M.expand_pending_char(typed)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local left = line:sub(1, col)

  for _, shortcut in ipairs(M.shortcuts) do
    local token = shortcut.token
    if token:sub(-#typed) == typed then
      local prefix = token:sub(1, #token - #typed)
      if prefix ~= '' and left:sub(-#prefix) == prefix then
        local start_col = col - #prefix
        local new_line = line:sub(1, start_col) .. shortcut.char .. line:sub(col + 1)
        vim.api.nvim_set_current_line(new_line)
        vim.api.nvim_win_set_cursor(0, { row, start_col + #shortcut.char })
        return true
      end
    end
  end

  return false
end

function M.completion_prefix(ctx)
  local col = ctx.cursor and ctx.cursor[2] or #ctx.line
  local left = ctx.line:sub(1, col)
  local start = left:match '()::&[%w]*$'
  if not start then
    return nil
  end

  return {
    start_col = start - 1,
    end_col = col,
  }
end

function M.sorted_names()
  local names = vim.tbl_keys(M.entities)
  table.sort(names)
  return names
end

return M
