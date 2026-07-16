#!/usr/bin/env node
// Normalize one retained MotionGen graph export, then optionally discard the XLSX.

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { FileBlob, SpreadsheetFile } from '@oai/artifact-tool';

const argumentsMap = parseArguments(process.argv.slice(2));
const required = [
  'input',
  'output',
  'receipt',
  'case',
  'kind',
  'id',
  'model-url',
  'model-id',
  'model-title',
  'app-version',
  'velocity-profile',
  'original-filename',
  'download-time-utc',
  'source-rpm',
  'target-rpm',
  'spatial-scale',
];
for (const name of required) {
  if (!(name in argumentsMap)) throw new Error(`Missing --${name}`);
}
if (!['joint', 'link'].includes(argumentsMap.kind)) throw new Error('--kind must be joint or link');

const inputPath = path.resolve(argumentsMap.input);
const outputPath = path.resolve(argumentsMap.output);
const receiptPath = path.resolve(argumentsMap.receipt);
rejectLegacy(outputPath);
const inputBytes = await fs.readFile(inputPath);
const inputSha256 = crypto.createHash('sha256').update(inputBytes).digest('hex');
const scriptPath = fileURLToPath(import.meta.url);
const normalizerSha256 = crypto.createHash('sha256').update(await fs.readFile(scriptPath)).digest('hex');

const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(inputPath));
if (workbook.worksheets.items.length !== 1) {
  throw new Error(`Expected exactly one MotionGen sheet, found ${workbook.worksheets.items.length}`);
}
const sheet = workbook.worksheets.getItemAt(0);
const used = sheet.getUsedRange(true);
const values = used.values;
if (!Array.isArray(values) || values.length < 2) throw new Error('MotionGen workbook has no data rows');
const header = values[0].map((value) => String(value ?? '').trim());
const lengthUnit = argumentsMap['length-unit'] ?? 'model-unit';
const angleUnit = argumentsMap['angle-unit'] ?? 'deg';
const expectedHeader =
  argumentsMap.kind === 'joint'
    ? [
        'Time [s]',
        `x [${lengthUnit}]`,
        `y [${lengthUnit}]`,
        `Displacement [${lengthUnit}]`,
        `Linear Vel. [${lengthUnit}/s]`,
        `Linear Accel. [${lengthUnit}/s^2]`,
      ]
    : [
        'Time [s]',
        `Theta [${angleUnit}]`,
        `Angular Vel. [${angleUnit}/s]`,
        `Angular Accel. [${angleUnit}/s^2]`,
      ];
if (JSON.stringify(header) !== JSON.stringify(expectedHeader)) {
  throw new Error(`Unexpected MotionGen header: ${JSON.stringify(header)}`);
}

const sourceRpm = numberArgument('source-rpm');
const targetRpm = numberArgument('target-rpm');
const spatialScale = numberArgument('spatial-scale');
const speedRatio = targetRpm / sourceRpm;
const rotation = JSON.parse(argumentsMap.rotation ?? '[[1,0],[0,1]]');
const translation = JSON.parse(argumentsMap.translation ?? '[0,0]');
const angleScale = angleUnit === 'deg' ? Math.PI / 180 : 1;
const dataRows = values.slice(1).filter((row) => row.some((value) => value !== null && value !== ''));
const normalized = dataRows.map((row, index) => {
  const time = numeric(row[0], index, 0) / speedRatio;
  if (argumentsMap.kind === 'joint') {
    const source = [numeric(row[1], index, 1), numeric(row[2], index, 2)];
    const x = spatialScale * (rotation[0][0] * source[0] + rotation[0][1] * source[1]) + translation[0];
    const y = spatialScale * (rotation[1][0] * source[0] + rotation[1][1] * source[1]) + translation[1];
    return [
      `motiongen_${String(index).padStart(4, '0')}`,
      time,
      x,
      y,
      spatialScale * speedRatio * numeric(row[4], index, 4),
      spatialScale * speedRatio * speedRatio * numeric(row[5], index, 5),
    ];
  }
  return [
    `motiongen_${String(index).padStart(4, '0')}`,
    time,
    angleScale * numeric(row[1], index, 1),
    speedRatio * angleScale * numeric(row[2], index, 2),
    speedRatio * speedRatio * angleScale * numeric(row[3], index, 3),
  ];
});

const outputHeader =
  argumentsMap.kind === 'joint'
    ? ['sample_id', 'time_s', 'x', 'y', 'speed', 'acceleration']
    : ['sample_id', 'time_s', 'theta_rad', 'omega_rad_s', 'alpha_rad_s2'];
const normalizedCsv =
  [outputHeader, ...normalized].map((row) => row.map(format).join(',')).join('\n') + '\n';
const normalizedCsvSha256 = crypto.createHash('sha256').update(normalizedCsv).digest('hex');
await fs.mkdir(path.dirname(outputPath), { recursive: true });
await fs.writeFile(outputPath, normalizedCsv, 'utf8');

const sourceQuantization = 0.0005;
const receipt = {
  schema_version: 1,
  case_id: argumentsMap.case,
  model_url: argumentsMap['model-url'],
  model_id: argumentsMap['model-id'],
  model_title: argumentsMap['model-title'],
  model_access: 'authenticated-account',
  motiongen_app_version: argumentsMap['app-version'],
  graph: { kind: argumentsMap.kind, id: argumentsMap.id },
  actuation: {
    profile: argumentsMap['velocity-profile'],
    source_rpm: sourceRpm,
    target_rpm: targetRpm,
    source_rad_s: (sourceRpm * Math.PI) / 30,
    target_rad_s: (targetRpm * Math.PI) / 30,
  },
  source_units: {
    time: 's',
    length: lengthUnit,
    angle: angleUnit,
  },
  original_filename: argumentsMap['original-filename'],
  original_xlsx_sha256: inputSha256,
  sheets: [{ name: sheet.name, header, row_count: normalized.length }],
  download_time_utc: argumentsMap['download-time-utc'],
  normalization_script_sha256: normalizerSha256,
  coordinate_transform: {
    spatial_scale: spatialScale,
    rotation,
    translation,
    speed_ratio: speedRatio,
  },
  quantization_bound: {
    position: sourceQuantization * spatialScale,
    speed: sourceQuantization * spatialScale * speedRatio,
    acceleration: sourceQuantization * spatialScale * speedRatio * speedRatio,
    angle: sourceQuantization * angleScale,
    angular_velocity: sourceQuantization * angleScale * speedRatio,
    angular_acceleration: sourceQuantization * angleScale * speedRatio * speedRatio,
  },
  terminal_null_columns: (argumentsMap['terminal-null-columns'] ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean),
  normalized_csv: path.basename(outputPath),
  normalized_csv_sha256: normalizedCsvSha256,
  original_discarded: argumentsMap['discard-input'] === 'true',
  renormalization_limitation:
    'The original XLSX is intentionally not committed; future normalization cannot be reproduced without re-exporting the retained MotionGen model.',
};
await fs.mkdir(path.dirname(receiptPath), { recursive: true });
await fs.writeFile(receiptPath, JSON.stringify(receipt, null, 2) + '\n', 'utf8');

if (argumentsMap['discard-input'] === 'true') await fs.unlink(inputPath);

function parseArguments(values) {
  const result = {};
  for (let index = 0; index < values.length; index += 2) {
    const name = values[index];
    if (!name?.startsWith('--') || index + 1 >= values.length) throw new Error(`Invalid argument ${name}`);
    result[name.slice(2)] = values[index + 1];
  }
  return result;
}

function numberArgument(name) {
  const value = Number(argumentsMap[name]);
  if (!Number.isFinite(value) || value === 0) throw new Error(`--${name} must be finite and nonzero`);
  return value;
}

function numeric(value, row, column) {
  const result = Number(value);
  if (!Number.isFinite(result)) throw new Error(`Non-numeric MotionGen cell at row ${row + 2}, column ${column + 1}`);
  return result;
}

function format(value) {
  return typeof value === 'number' ? value.toPrecision(17).replace(/(?:\.0+|(?:(\.\d*?)0+))(?=e|$)/, '$1') : String(value);
}

function rejectLegacy(value) {
  const normalizedPath = value.replaceAll('\\', '/');
  if (normalizedPath.includes('/legacy/') || normalizedPath.includes('/CSVOutput')) {
    throw new Error(`v1 normalizer rejects legacy output path ${value}`);
  }
}
