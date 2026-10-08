// Export DLI site and program-move tables for the Quarto pages, using the map app's own data and
// helpers so the tables say exactly what the map shows:
//   sites: immersion school labels on the scenario school maps (public/data/<scenario>_<band>_schools.geojson),
//          read with programs.mjs immersionSites (own_area = the school has its own neighborhood area)
//   moves: language program moves transcribed from the Oct 2026 board memo (src/lib/changes-data.mjs);
//          the grade band is the one whose maps show both ends (programs.mjs programMoves).
//          kind = 'program' for a program move, 'grades' for a K-8 whose middle grades (and so its
//          6-8 immersion strand) move to a middle school (César Chávez -> George)
//
// Usage: node data-raw/export_dli_tables.mjs  ->  data/dli_sites.csv, data/dli_moves.csv
import { readFileSync, writeFileSync } from 'node:fs'
import { CHANGES, SOURCES } from '../src/lib/changes-data.mjs'
import { closes, schoolKey } from '../src/lib/changes.mjs'
import { immersionSites, programKind, programMoves } from '../src/lib/programs.mjs'

const root = new URL('..', import.meta.url)
const read = (k) => JSON.parse(readFileSync(new URL(`public/data/${k}.geojson`, root)))
const SCENARIOS = ['sq', 'a', 'b']
const BANDS = { k5: 'K-5', 68: '6-8', 912: '9-12' }
const LANGUAGES = ['Spanish', 'Mandarin', 'Japanese', 'Russian', 'Vietnamese']
// Map name key -> school name in the PPS enrollment PDFs (data/dli_track_profiles.csv etc.), where they differ
const PPS_NAMES = { brentwood: 'Lane' }

const csv = (rows, cols) => [cols.join(','), ...rows.map((r) => cols.map((c) => {
  const v = r[c] ?? ''
  return /[",\n]/.test(String(v)) ? `"${String(v).replace(/"/g, '""')}"` : v
}).join(','))].join('\n') + '\n'
const round = (x) => Math.round(x * 1e6) / 1e6

// ---- sites -------------------------------------------------------------------------------------
const sitesBy = {} // `${scenario}_${band}` -> Map(`${key}|${language}` -> row)
for (const s of SCENARIOS) for (const b of Object.keys(BANDS)) {
  const areaKeys = new Set(read(`${s}_${b}`).features.map((f) => schoolKey(String(f.properties.name))))
  const m = new Map()
  for (const site of immersionSites(read(`${s}_${b}_schools`), areaKeys)) for (const language of site.languages) {
    m.set(`${site.key}|${language}`, {
      scenario: s, band: BANDS[b], school: site.short, school_key: site.key, pps_school: PPS_NAMES[site.key] ?? site.short,
      language, map_label: site.name,
      own_area: site.ownArea, lon: round(site.coords[0]), lat: round(site.coords[1]),
    })
  }
  sitesBy[`${s}_${b}`] = m
}

const sites = []
for (const b of Object.keys(BANDS)) {
  const sq = sitesBy[`sq_${b}`]
  for (const s of SCENARIOS) {
    const cur = sitesBy[`${s}_${b}`]
    for (const [k, r] of cur) sites.push({ ...r, change: s === 'sq' ? '' : sq.has(k) ? 'kept' : 'added' })
    // sites that exist today but not in this scenario: keep a row so the scorecard can count losses
    if (s !== 'sq') for (const [k, r] of sq) if (!cur.has(k)) sites.push({ ...r, scenario: s, change: 'removed', own_area: '' })
  }
}
const order = (r) => [SCENARIOS.indexOf(r.scenario), Object.values(BANDS).indexOf(r.band), LANGUAGES.indexOf(r.language), r.school]
sites.sort((x, y) => { const a = order(x), b = order(y); for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1; return 0 })

// ---- moves -------------------------------------------------------------------------------------
const moves = []
for (const s of ['a', 'b']) {
  const banded = new Map() // `${from}|${to}|${program}` -> band, from the maps
  for (const b of Object.keys(BANDS)) {
    for (const m of programMoves(s, { scenarioSchools: read(`${s}_${b}_schools`), sqSchools: read(`sq_${b}_schools`) }))
      banded.set(`${m.fromName}|${m.toName}|${m.program}`, { band: BANDS[b], from: m.from, to: m.to })
  }
  for (const e of CHANGES[s]) {
    if (e.kind !== 'program') continue
    const language = programKind(e.program)
    if (!LANGUAGES.includes(language)) continue // Deaf and Hard of Hearing, Odyssey
    for (const from of e.from) {
      const g = banded.get(`${from}|${e.to}|${e.program}`)
      if (!g) console.error(`warning: ${s} ${e.program} ${from} -> ${e.to} is not drawn on any grade band map`)
      moves.push({
        scenario: s, kind: 'program', language, program: e.program, band: g?.band ?? '',
        from_school: from, from_key: schoolKey(from), from_closes: closes(s, from),
        to_school: e.to, to_key: schoolKey(e.to),
        from_lon: g ? round(g.from[0]) : '', from_lat: g ? round(g.from[1]) : '',
        to_lon: g ? round(g.to[0]) : '', to_lat: g ? round(g.to[1]) : '',
        detail: e.detail ?? '', source: SOURCES[e.source] ?? e.source,
      })
    }
  }

  // K-8 schools whose middle grades move: their 6-8 immersion strand goes with them
  for (const e of CHANGES[s]) {
    if (e.kind !== 'grades') continue
    const key = schoolKey(e.school)
    for (const r of sitesBy.sq_68.values()) {
      if (r.school_key !== key) continue
      const to = [...sitesBy[`${s}_68`].values()].find((x) => x.school_key === schoolKey(e.to) && x.language === r.language)
      if (!to) console.error(`warning: ${s} ${e.school} 6-8 ${r.language} moves to ${e.to}, which has no ${r.language} site`)
      moves.push({
        scenario: s, kind: 'grades', language: r.language, program: `${r.language} immersion (grades 6-8 move)`, band: '6-8',
        from_school: e.school, from_key: key, from_closes: closes(s, e.school), to_school: e.to, to_key: schoolKey(e.to),
        from_lon: r.lon, from_lat: r.lat, to_lon: to?.lon ?? '', to_lat: to?.lat ?? '',
        detail: `${e.school} becomes K-5; its grades 6-8 move to ${e.to}.`, source: SOURCES[e.source] ?? e.source,
      })
    }
  }
}

// ---- checks ------------------------------------------------------------------------------------
// Every site a scenario removes should be explained by a memo move out of that school in that language.
for (const r of sites.filter((x) => x.change === 'removed')) {
  const ok = moves.some((m) => m.scenario === r.scenario && m.from_key === r.school_key && m.language === r.language)
  if (!ok) console.error(`note: ${r.scenario} ${r.band} ${r.language} at ${r.school} disappears from the map with no memo move`)
}
// Join keys should match the PPS immersion enrollment table for the current year.
const profiles = readFileSync(new URL('data/dli_track_profiles.csv', root), 'utf8').trim().split('\n').slice(1)
  .map((l) => l.split(',')).filter((f) => f[0] === '2025-26').map((f) => f[1])
const unmatched = [...new Set(sites.filter((r) => r.scenario === 'sq').map((r) => r.pps_school))].filter((k) => !profiles.includes(k))
if (unmatched.length) console.error('note: status quo sites not in dli_track_profiles 2025-26:', unmatched.join(', '))

writeFileSync(new URL('data/dli_sites.csv', root), csv(sites,
  ['scenario', 'band', 'language', 'school', 'school_key', 'pps_school', 'change', 'own_area', 'map_label', 'lon', 'lat']))
writeFileSync(new URL('data/dli_moves.csv', root), csv(moves,
  ['scenario', 'kind', 'language', 'program', 'band', 'from_school', 'from_key', 'from_closes', 'to_school', 'to_key',
    'from_lon', 'from_lat', 'to_lon', 'to_lat', 'detail', 'source']))
for (const s of SCENARIOS) {
  const n = (c) => sites.filter((r) => r.scenario === s && r.change === c).length
  console.log(`${s}: ${sites.filter((r) => r.scenario === s && r.change !== 'removed').length} sites` +
    (s === 'sq' ? '' : ` (${n('kept')} kept, ${n('added')} added, ${n('removed')} removed); ${moves.filter((m) => m.scenario === s).length} moves`))
}
console.log('wrote data/dli_sites.csv, data/dli_moves.csv')
