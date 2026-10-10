// Export the enabled scene's FINAL level context, not assembleScenePlan({}, plan).
// This never writes data/original; Godot additions live in OrchardLevel.plan().
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath, pathToFileURL} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.resolve(root, '../../web/Pixi-Battlefield1-Blue');
const load = relative => import(pathToFileURL(path.join(source, relative)).href);
const warnings = [];
const originalWarn = console.warn;
console.warn = (...parts) => warnings.push(parts);
let LEVELS;
try { ({LEVELS} = await load('src/levels.js')); } finally { console.warn = originalWarn; }
const {ASSAULT_RULES} = await load('src/assaultRules.js');
const scenes = JSON.parse(fs.readFileSync(path.join(source, 'src/map-kit/scenes.json'), 'utf8'));
const scene = scenes.scenes.find(item => item.id === 'level-01');
const level = LEVELS[0];
assert.equal(scene.enabled, true);
assert.equal(level.mapKit.sceneId, 'level-01');
assert.equal(level.allies.length, 29);
assert.equal(level.enemies.length, 30);
// Game.applyForceComposition() is inactive on this formal level. If source authors
// enable that later, stop the export until its final class loadouts are included.
assert.equal(level.blueForceComposition, undefined);
assert.equal(level.redForceComposition, undefined);

const sourceFiles = ['src/levels.js', 'src/scenePlanLevel.js', 'src/map-kit/scenePlan.js',
  'src/map-kit/scenes.json', 'src/assaultRules.js', 'src/Game.js', 'src/objectives.js',
  'src/specialWeaponMigration.js'];
const hashes = Object.fromEntries(sourceFiles.map(name => [name,
  createHash('sha256').update(fs.readFileSync(path.join(source, name))).digest('hex')]));
const deployment = {player: level.player};
const specialCounts = {};
for (const team of ['blue', 'red']) {
  const replacement = level[`${team}Replacement`];
  const units = team === 'blue' ? level.allies : level.enemies;
  assert.equal(replacement.maxActive, 30);
  assert.equal(replacement.totalForce, 120);
  assert.equal(replacement.loadouts.length, 90);
  deployment[team] = {...scene.deployment[team], maxActive: replacement.maxActive,
    totalForce: replacement.totalForce, spawnPoints: replacement.spawnPoints,
    replacementLoadouts: replacement.loadouts};
  const loadouts = [...units.map(unit => unit.loadout), ...replacement.loadouts];
  if (team === 'blue') loadouts.push(level.player.loadout);
  assert.equal(loadouts.length, 120);
  specialCounts[team] = loadouts.filter(loadout => loadout[3] === 'Portable Mortar').length;
  assert.equal(specialCounts[team], team === 'blue' ? 3 : 2);
}
const exported = {
  format: 'little-battlefield-campaign-rules', version: 1,
  source: {sceneId: scene.id, levelId: level.id, hashes,
    extraction: 'LEVELS[0] after applyScenePlans and normalizeControlPoints',
    forceComposition: 'absent; Game.applyForceComposition leaves loadouts unchanged',
    warnings: warnings.filter(parts => String(parts[0]).includes('Scene level-01')),
    specialCounts},
  rules: {
    captureTime: level.objective.captureTime,
    replacementWaveSeconds: ASSAULT_RULES.replacementWaveSeconds,
    replacementWaveSize: ASSAULT_RULES.replacementWaveSize,
    handoffSeconds: ASSAULT_RULES.handoffSeconds,
    capture: {soloRate: 1, multipleRate: 1.18, contestedBase: .48, contestedBalance: .32},
    victory: {allControlPointsBlue: true, redEliminatedWithReservesExhausted: true},
    death: {handoffNearestLivingAlly: true, noLivingAllyDefeatEvenWithReserves: true},
    blueCapIncludesPlayer: true,
  },
  units: {blue: level.allies, red: level.enemies}, deployment,
  controlPoints: level.controlPoints, objective: level.objective,
  ai: {blue: level.blueAI, red: level.redAI},
};
const target = path.join(root, 'data/campaign/level01_rules.json');
fs.mkdirSync(path.dirname(target), {recursive: true});
fs.writeFileSync(target, JSON.stringify(exported, null, 2) + '\n');
console.log(JSON.stringify({target, blue: level.allies.length + 1, red: level.enemies.length,
  reservePerTeam: 90, specialCounts, captureTime: exported.rules.captureTime,
  replacementWaveSeconds: exported.rules.replacementWaveSeconds,
  sourceWarnings: exported.source.warnings.length}));
