// cspell:ignore PCAM
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

import { AiError } from './ai';
import { BUCKET, resetEmulators } from './emulator.test-support';
import { sweepCasesHandler } from './cases';
import { readObject, saveObject } from './case-support';
import { later, seedWorld, type World } from './case.test-support';
import {
  CONFIDENCE_CALIBRATION_NOTE,
  PREREAD_MAX_TILES,
  applyModelConfidenceCap,
  decodeImage,
  downscaleByFactor,
  draftNumbersMatch,
  encodeJpeg,
  encodePng,
  histologyDraft,
  histologyMeasurements,
  isJpeg,
  isPng,
  tileBudgetFactor,
  upscaleNearest,
  type Tile,
} from './preread-measure';
import { PROVENANCE } from './seed-cases-media';
import { ThinkingLevel } from '@google/genai';

import { GEMINI_TEXT_MODEL, type GeminiGenerate, type GeminiGenerateRequest } from './ai-gemini';
import {
  PREREAD_BATCH_CONCURRENCY,
  PREREAD_FEW_SHOT_INSTRUCTION,
  PREREAD_IMAGE_TEXT_RULE,
  PREREAD_MAX_IMAGES_PER_REQUEST,
  PREREAD_PCAM_LABEL_RULE,
  PREREAD_PROMPT_VERSION,
  PREREAD_TILES_PER_REQUEST,
  PREREAD_TILE_PX,
  PREREAD_CALL_TIMEOUT_MS,
  PREREAD_TILE_MAX_RETRIES,
  PREREAD_TILE_RETRY_BACKOFF_MS,
  PREREAD_WORKER_TIMEOUT_MS,
  TILE_THINKING_LEVEL,
  TILE_UPSCALE_FACTOR,
  assertPathsUnder,
  buildClassifyInstructions,
  buildClassifyRequestBody,
  buildClassifyUserContent,
  classifyInBatches,
  commitIfStillRunning,
  countClassifyImages,
  failureReasonOf,
  httpStatusClass,
  loadFewShotFixtures,
  parseClassifyTiles,
  processQueuedPreread,
  upscaleTilePng,
  type ClassifiedTile,
  type PrereadCache,
  type PrereadTileCallLog,
  type PrereadFailureLog,
  type PrereadVision,
  type TileCrop,
  PrereadCallError,
} from './preread-worker';

function solidRaster(width: number, height: number, rgb: [number, number, number]) {
  const data = Buffer.alloc(width * height * 3);
  for (let i = 0; i < width * height; i++) data.set(rgb, i * 3);
  return { width, height, channels: 3 as const, data };
}

function solidPng(width: number, height: number, rgb: [number, number, number]): Buffer {
  return encodePng(solidRaster(width, height, rgb));
}

function solidJpeg(width: number, height: number, rgb: [number, number, number]): Buffer {
  return encodeJpeg(solidRaster(width, height, rgb), 95);
}

function tileIdsOf(req: GeminiGenerateRequest): string[] {
  const parts = (req.contents as { parts: { text?: string }[] }[])[0].parts;
  const ids: string[] = [];
  for (const part of parts) {
    const match = typeof part.text === 'string' ? /tile id=(\S+)/.exec(part.text) : null;
    if (match) ids.push(match[1]);
  }
  return ids;
}

/** Stays open until the tile timeout aborts the signal on the request. */
function hangUntilAbort(req: GeminiGenerateRequest, signals: AbortSignal[]): Promise<{ text: string }> {
  const signal = req.config?.abortSignal;
  if (!signal) return Promise.reject(new Error('missing abort signal'));
  signals.push(signal);
  return new Promise((_, reject) => {
    signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
  });
}

const oneTile = {
  bytes: solidPng(96, 96, [1, 2, 3]),
  contentType: 'image/png',
  name: 'slide-0.png',
  width: 96,
  height: 96,
};

function fakeVision(label = 'Normal'): PrereadVision {
  return {
    async classify(crops: TileCrop[]): Promise<ClassifiedTile[]> {
      return crops.map((c) => ({ id: c.id, label, probability: 0.91 }));
    },
  };
}

/** Labels chosen tiles by crop id (`img0-tile-0-0`); everything else is Normal. */
function visionById(tumourIds: string[]): PrereadVision {
  const set = new Set(tumourIds);
  return {
    async classify(crops: TileCrop[]): Promise<ClassifiedTile[]> {
      return crops.map((c) => ({
        id: c.id,
        label: set.has(c.id) ? 'Tumour' : 'Normal',
        probability: 0.91,
      }));
    },
  };
}

describe('preread-measure', () => {
  it('rule 2: draft numbers equal the measurement record', () => {
    const tiles: Tile[] = [
      {
        id: 'tile-0-0',
        imageUid: 'img',
        label: 'Tumour',
        probability: 0.9,
        row: 0,
        col: 0,
        source: 's',
      },
      {
        id: 'tile-0-1',
        imageUid: 'img',
        label: 'Normal',
        probability: 0.9,
        row: 0,
        col: 1,
        source: 's',
      },
    ];
    const measurements = histologyMeasurements(tiles, { rows: 1, cols: 2, tilePx: 96 }, 0.25);
    const draft = histologyDraft(tiles, measurements);
    assert.equal(draftNumbersMatch(draft, measurements, tiles.length), true);
    const forged = {
      ...draft,
      impression: 'Tumour spans 99 mm somehow.',
    };
    assert.equal(draftNumbersMatch(forged, measurements, tiles.length), false);
  });

  it('decodes a real JPEG and a real PNG by file signature', () => {
    const pngBytes = solidPng(32, 24, [10, 20, 30]);
    const jpegBytes = solidJpeg(32, 24, [40, 50, 60]);
    assert.equal(isPng(pngBytes), true);
    assert.equal(isJpeg(pngBytes), false);
    assert.equal(isJpeg(jpegBytes), true);
    assert.equal(isPng(jpegBytes), false);

    const fromPng = decodeImage(pngBytes);
    assert.equal(fromPng.width, 32);
    assert.equal(fromPng.height, 24);
    assert.equal(fromPng.channels, 3);
    assert.deepEqual([...fromPng.data.subarray(0, 3)], [10, 20, 30]);

    const fromJpeg = decodeImage(jpegBytes);
    assert.equal(fromJpeg.width, 32);
    assert.equal(fromJpeg.height, 24);
    assert.equal(fromJpeg.channels, 3);
    // Lossy: channel values stay near the solid fill.
    assert.ok(Math.abs(fromJpeg.data[0] - 40) < 15);
    assert.ok(Math.abs(fromJpeg.data[1] - 50) < 15);
    assert.ok(Math.abs(fromJpeg.data[2] - 60) < 15);

    assert.throws(() => decodeImage(Buffer.from('not-an-image')), /unsupported image/);
  });

  it('oversized slides resize by a whole factor and keep at most 64 tiles', () => {
    // 10×10 tiles of 96px would be 100 tiles without a cap.
    const width = 10 * PREREAD_TILE_PX;
    const height = 10 * PREREAD_TILE_PX;
    const factor = tileBudgetFactor(width, height, PREREAD_TILE_PX);
    assert.ok(factor > 1);
    const scaled = downscaleByFactor(solidRaster(width, height, [1, 2, 3]), factor);
    const cols = Math.floor(scaled.width / PREREAD_TILE_PX);
    const rows = Math.floor(scaled.height / PREREAD_TILE_PX);
    assert.ok(rows * cols <= PREREAD_MAX_TILES);
    assert.equal(scaled.width, Math.floor(width / factor));
    assert.equal(scaled.height, Math.floor(height / factor));
    // Factor 1 stays put; mpp scales with the factor outside this helper.
    assert.equal(tileBudgetFactor(192, 96, PREREAD_TILE_PX), 1);
  });
});

describe('preread-worker helpers', () => {
  it('rule 1: storage paths must stay under preread/{case}/{run}/', () => {
    assert.doesNotThrow(() =>
      assertPathsUnder('c1', 'r1', ['preread/c1/r1/labels.json', 'preread/c1/r1/heatmap.png']),
    );
    assert.throws(() => assertPathsUnder('c1', 'r1', ['cases/c1/secret.json']));
  });

  it('rule 4: maps errors to Failed reasons', () => {
    assert.equal(failureReasonOf(new AiError('Timeout')), 'Timeout');
    assert.equal(failureReasonOf(new AiError('OffSchema')), 'OffSchema');
    assert.equal(failureReasonOf(new Error('boom')), 'ServiceError');
  });
});

describe('processQueuedPreread', () => {
  let w: World;

  beforeEach(async () => {
    await resetEmulators();
    w = await seedWorld();
  });

  async function queuedRun(opts?: {
    enabled?: boolean;
    vision?: PrereadVision;
    cache?: PrereadCache;
    /** Default: small PNG (192×96 → two tiles). */
    slide?: { bytes: Buffer; contentType: string; name: string; width: number; height: number };
    /** Two or more slides; overrides `slide` when present. */
    slides?: { bytes: Buffer; contentType: string; name: string }[];
    micronsPerPixel?: number;
    generate?: GeminiGenerate;
    callTimeoutMs?: number;
    workerTimeoutMs?: number;
    fewShot?: false;
    retryLog?: (entry: { reason: string; attempt: number }) => void;
    callLog?: (entry: PrereadTileCallLog) => void;
  }): Promise<{ caseUid: string; runUid: string }> {
    const caseUid = randomUUID();
    const runUid = randomUUID();
    const slides = opts?.slides ?? [
      opts?.slide ?? {
        bytes: solidPng(192, 96, [200, 180, 160]),
        contentType: 'image/png',
        name: 'slide-0.png',
        width: 192,
        height: 96,
      },
    ];
    const imagePaths: string[] = [];
    for (const slide of slides) {
      const imagePath = `cases/${caseUid}/slides/${slide.name}`;
      await saveObject(BUCKET, imagePath, slide.bytes, slide.contentType);
      imagePaths.push(imagePath);
    }
    await w.deps.db.collection('cases').doc(caseUid).set({
      uid: caseUid,
      currentStage: 'PrereadQueued',
      prereadRunUid: runUid,
      pathologistUid: w.pathologist.uid,
      participantUids: [w.pathologist.uid],
    });
    await w.deps.db
      .collection('cases')
      .doc(caseUid)
      .collection('preread')
      .doc(runUid)
      .set({
        uid: runUid,
        caseUid,
        profile: 'Cancer',
        status: 'Queued',
        imagePaths,
        micronsPerPixel: opts?.micronsPerPixel ?? 0.25,
        segmentationPath: '',
        labelsPath: '',
        labelCounts: {},
        measurements: {},
        draft: {
          findings: [],
          impression: '',
          confidence: 0,
          confidenceBand: '',
          urgency: '',
          nextSteps: [],
        },
        models: {},
        inputLanguage: 'en',
        failureReason: '',
        requestedAt: '2026-11-03T00:00:00.000Z',
        startedAt: '',
        readyAt: '',
        lastUpdatedAt: '2026-11-03T00:00:00.000Z',
      });

    await processQueuedPreread(
      { ...w.deps, bucket: BUCKET, config: { enabled: () => opts?.enabled !== false } },
      caseUid,
      runUid,
      {
        enabled: opts?.enabled ?? true,
        vision: opts?.generate ? opts.vision : (opts?.vision ?? fakeVision('Normal')),
        cache: opts?.cache,
        generate: opts?.generate,
        callTimeoutMs: opts?.callTimeoutMs,
        workerTimeoutMs: opts?.workerTimeoutMs,
        fewShot: opts?.fewShot,
        retryLog: opts?.retryLog,
        callLog: opts?.callLog,
      },
    );
    return { caseUid, runUid };
  }

  it('rule 6: preread_enabled off does no work', async () => {
    const { caseUid, runUid } = await queuedRun({ enabled: false });
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Queued');
  });

  it('rule 2+8: Ready draft numbers match labels; models record prompt version', async () => {
    const { caseUid, runUid } = await queuedRun({ vision: fakeVision('Tumour') });
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Ready');
    assert.equal(run?.models?.classify, GEMINI_TEXT_MODEL);
    assert.equal(run?.models?.promptVersion, PREREAD_PROMPT_VERSION);
    assert.equal(run?.models?.tileUpscale, String(TILE_UPSCALE_FACTOR));
    // Model runs never claim High until calibrated.
    assert.notEqual(run?.draft?.confidenceBand, 'High');
    assert.ok(String(run?.labelsPath).startsWith(`preread/${caseUid}/${runUid}/`));
    assert.ok(String(run?.segmentationPath).startsWith(`preread/${caseUid}/${runUid}/`));
    assert.equal(
      draftNumbersMatch(run?.draft, run?.measurements as Record<string, number>, 2),
      true,
    );
  });

  it('a focus never joins tiles from two slides', async () => {
    // Different bytes per slide: identical slides share a cache key.
    const slide = (name: string, shade: number) => ({
      bytes: solidPng(192, 96, [200, 180, shade]),
      contentType: 'image/png',
      name,
    });
    // Merged, (0,1) and (0,0) touch; measured per slide they are two lone tiles.
    const { caseUid, runUid } = await queuedRun({
      vision: visionById(['img0-tile-0-1', 'img1-tile-0-0']),
      slides: [slide('slide-0.png', 160), slide('slide-1.png', 161)],
    });
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Ready');
    assert.equal(run?.measurements?.tumourTiles, 2);
    assert.equal(run?.measurements?.largestFocusMm, 0.02);
  });

  it('each slide keeps its own resize scale', async () => {
    const { caseUid, runUid } = await queuedRun({
      vision: visionById(['img0-tile-0-0', 'img0-tile-0-1', 'img1-tile-0-0']),
      slides: [
        { bytes: solidPng(192, 96, [200, 180, 160]), contentType: 'image/png', name: 'slide-0.png' },
        { bytes: solidPng(768, 768, [200, 180, 160]), contentType: 'image/png', name: 'slide-1.png' },
      ],
    });
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Ready');
    // Slide 0: two tiles at mpp 0.25 → 0.05; slide 1: one tile at mpp 0.5 → 0.05.
    // At the merged scale both slides would measure 0.1.
    assert.equal(run?.measurements?.largestFocusMm, 0.05);
    assert.equal(run?.measurements?.tumourTiles, 3);
  });

  it('one slide measures exactly as before', async () => {
    const { caseUid, runUid } = await queuedRun({ vision: fakeVision('Tumour') });
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Ready');
    assert.deepEqual(run?.measurements, {
      tumourTiles: 2,
      normalTiles: 0,
      unknownTiles: 0,
      tumourAreaPercent: 100,
      largestFocusMm: 0.05,
    });
  });

  it('a full first slide leaves room for the second', async () => {
    // 768×768 wants all 64 tiles at full size; the share drops it to 16, and the
    // second slide still completes.
    const { caseUid, runUid } = await queuedRun({
      vision: fakeVision('Normal'),
      slides: [
        { bytes: solidPng(768, 768, [200, 180, 160]), contentType: 'image/png', name: 'slide-0.png' },
        { bytes: solidPng(192, 96, [200, 180, 160]), contentType: 'image/png', name: 'slide-1.png' },
      ],
    });
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Ready');
    assert.equal(run?.labelCounts?.Normal, 18);
  });

  it('the heatmap is the first slide, the one the viewer shows', async () => {
    const { caseUid, runUid } = await queuedRun({
      vision: fakeVision('Normal'),
      slides: [
        { bytes: solidPng(192, 96, [200, 180, 160]), contentType: 'image/png', name: 'slide-0.png' },
        { bytes: solidPng(384, 288, [200, 180, 160]), contentType: 'image/png', name: 'slide-1.png' },
      ],
    });
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    const png = await readObject(BUCKET, String(run?.segmentationPath));
    assert.ok(png);
    // PNG header: width and height are the 4-byte values at offsets 16 and 20.
    assert.equal(png.readUInt32BE(16), 192);
    assert.equal(png.readUInt32BE(20), 96);
  });

  it('an impossible set fails before any model call', async () => {
    const caseUid = randomUUID();
    const runUid = randomUUID();
    const imagePaths = Array.from({ length: 65 }, (_, i) => `cases/${caseUid}/slides/fake-${i}.png`);
    await w.deps.db.collection('cases').doc(caseUid).set({
      uid: caseUid,
      currentStage: 'PrereadQueued',
      prereadRunUid: runUid,
      pathologistUid: w.pathologist.uid,
      participantUids: [w.pathologist.uid],
    });
    await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).set({
      uid: runUid,
      caseUid,
      profile: 'Cancer',
      status: 'Queued',
      imagePaths,
      micronsPerPixel: 0.25,
      segmentationPath: '',
      labelsPath: '',
      labelCounts: {},
      measurements: {},
      draft: {
        findings: [],
        impression: '',
        confidence: 0,
        confidenceBand: '',
        urgency: '',
        nextSteps: [],
      },
      models: {},
      inputLanguage: 'en',
      failureReason: '',
      requestedAt: '2026-11-03T00:00:00.000Z',
      startedAt: '',
      readyAt: '',
      lastUpdatedAt: '2026-11-03T00:00:00.000Z',
    });
    let calls = 0;
    await processQueuedPreread(
      { ...w.deps, bucket: BUCKET, config: { enabled: () => true } },
      caseUid,
      runUid,
      {
        enabled: true,
        generate: (async () => {
          calls += 1;
          throw new Error('must not call');
        }) as GeminiGenerate,
      },
    );
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Failed');
    assert.equal(run?.failureReason, 'OffSchema');
    assert.equal(calls, 0);
  });

  it('rule 7: a label outside the allowed set becomes Unknown', async () => {
    const vision: PrereadVision = {
      async classify(crops) {
        return crops.map((c) => ({ id: c.id, label: 'Adenocarcinoma', probability: 0.99 }));
      },
    };
    const { caseUid, runUid } = await queuedRun({ vision });
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Ready');
    assert.equal(run?.labelCounts?.Unknown, 2);
    assert.equal(run?.labelCounts?.Tumour, undefined);
  });

  it('rule 3: a second pass of the same image hits the cache (no second classify)', async () => {
    let calls = 0;
    const vision: PrereadVision = {
      async classify(crops) {
        calls += 1;
        return crops.map((c) => ({ id: c.id, label: 'Normal', probability: 0.9 }));
      },
    };
    const store = new Map<string, ClassifiedTile[]>();
    const cache: PrereadCache = {
      get: async (key) => store.get(key),
      set: async (key, labels) => {
        store.set(key, labels);
      },
    };
    const first = await queuedRun({ vision, cache });
    const firstCalls = calls;
    assert.ok(firstCalls >= 1);
    // Reset the run to Queued and process again with the same cache.
    await w.deps.db
      .collection('cases')
      .doc(first.caseUid)
      .collection('preread')
      .doc(first.runUid)
      .update({ status: 'Queued', startedAt: '', readyAt: '', failureReason: '' });
    await processQueuedPreread(
      { ...w.deps, bucket: BUCKET },
      first.caseUid,
      first.runUid,
      { enabled: true, vision, cache },
    );
    assert.equal(calls, firstCalls, 'cache must prevent a second model call');
    const run = (
      await w.deps.db
        .collection('cases')
        .doc(first.caseUid)
        .collection('preread')
        .doc(first.runUid)
        .get()
    ).data();
    assert.equal(run?.status, 'Ready');
  });

  it('rule 4: a vision OffSchema failure records Failed, never Ready', async () => {
    const vision: PrereadVision = {
      async classify() {
        throw new AiError('OffSchema');
      },
    };
    const { caseUid, runUid } = await queuedRun({ vision });
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Failed');
    assert.equal(run?.failureReason, 'OffSchema');
  });

  it('rule 5: vision errors do not put image bytes in the message', async () => {
    const vision: PrereadVision = {
      async classify() {
        throw new AiError('ServiceError');
      },
    };
    const { caseUid, runUid } = await queuedRun({ vision });
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.failureReason, 'ServiceError');
    assert.ok(!JSON.stringify(run).includes('data:image'));
  });

  it('a hung tile is aborted and three timeouts fail the run', async () => {
    const signals: AbortSignal[] = [];
    const retries: { reason: string; attempt: number }[] = [];
    let calls = 0;
    const generate: GeminiGenerate = (req) => {
      calls += 1;
      return hangUntilAbort(req, signals);
    };
    const { caseUid, runUid } = await queuedRun({
      generate,
      callTimeoutMs: 30,
      workerTimeoutMs: 5_000,
      fewShot: false,
      retryLog: (entry) => retries.push(entry),
      slide: oneTile,
    });
    assert.equal(calls, 3);
    assert.equal(signals.length, 3);
    assert.ok(signals.every((signal) => signal.aborted));
    assert.deepEqual(retries, [
      { reason: 'Timeout', attempt: 2 },
      { reason: 'Timeout', attempt: 3 },
    ]);
    for (const entry of retries) {
      const serialised = JSON.stringify(entry);
      assert.deepEqual(Object.keys(entry).sort(), ['attempt', 'reason']);
      assert.ok(!serialised.includes('data:image'));
      assert.ok(!serialised.includes('Normal'));
      assert.ok(!serialised.includes('Tumour'));
    }
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Failed');
    assert.equal(run?.failureReason, 'Timeout');
  });

  it('a later success after aborted timeouts keeps the run', async () => {
    const signals: AbortSignal[] = [];
    let calls = 0;
    const generate: GeminiGenerate = (req) => {
      calls += 1;
      if (calls < 3) return hangUntilAbort(req, signals);
      const signal = req.config?.abortSignal;
      assert.ok(signal);
      signals.push(signal);
      return Promise.resolve({
        text: JSON.stringify({
          tiles: tileIdsOf(req).map((id) => ({ id, label: 'Normal', probability: 0.9 })),
        }),
      });
    };
    const { caseUid, runUid } = await queuedRun({
      generate,
      callTimeoutMs: 30,
      workerTimeoutMs: 5_000,
      fewShot: false,
      slide: oneTile,
    });
    assert.equal(calls, 3);
    assert.equal(signals[0].aborted, true);
    assert.equal(signals[1].aborted, true);
    assert.equal(signals[2].aborted, false);
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Ready');
  });

  it('an OffSchema answer is not retried', async () => {
    let calls = 0;
    const generate: GeminiGenerate = () => {
      calls += 1;
      return Promise.resolve({ text: 'not-json' });
    };
    const { caseUid, runUid } = await queuedRun({
      generate,
      fewShot: false,
      slide: oneTile,
      workerTimeoutMs: 5_000,
    });
    assert.equal(calls, 1);
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Failed');
    assert.equal(run?.failureReason, 'OffSchema');
  });

  it('a real JPEG slide reaches Ready', async () => {
    const { caseUid, runUid } = await queuedRun({
      slide: {
        bytes: solidJpeg(192, 96, [120, 100, 80]),
        contentType: 'image/jpeg',
        name: 'slide-0.jpg',
        width: 192,
        height: 96,
      },
    });
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Ready');
    assert.equal(run?.labelCounts?.Normal, 2);
  });

  it('an oversized PNG is downscaled; mpp is adjusted and recorded', async () => {
    // 10×10 tiles → factor > 1 under the 64-tile cap.
    const side = 10 * PREREAD_TILE_PX;
    let seenCrops = 0;
    const vision: PrereadVision = {
      async classify(crops) {
        seenCrops += crops.length;
        return crops.map((c) => ({ id: c.id, label: 'Normal', probability: 0.9 }));
      },
    };
    const { caseUid, runUid } = await queuedRun({
      vision,
      micronsPerPixel: 0.5,
      slide: {
        bytes: solidPng(side, side, [1, 2, 3]),
        contentType: 'image/png',
        name: 'big.png',
        width: side,
        height: side,
      },
    });
    assert.ok(seenCrops <= PREREAD_MAX_TILES);
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Ready');
    const labelsBytes = await readObject(BUCKET, String(run?.labelsPath));
    assert.ok(labelsBytes);
    const labels = JSON.parse(labelsBytes.toString('utf8')) as {
      grid: { tileScale: number; micronsPerPixel: number; sourceMicronsPerPixel: number };
    };
    assert.ok(labels.grid.tileScale > 1);
    assert.equal(labels.grid.sourceMicronsPerPixel, 0.5);
    assert.equal(labels.grid.micronsPerPixel, 0.5 * labels.grid.tileScale);
    assert.equal(run?.models?.tileScale, String(labels.grid.tileScale));
    assert.equal(
      draftNumbersMatch(run?.draft, run?.measurements as Record<string, number>, seenCrops),
      true,
    );
  });

  it('logs each settled tile call and never the image, the label or an id', async () => {
    const logs: PrereadTileCallLog[] = [];
    const generate: GeminiGenerate = async (req) => ({
      text: JSON.stringify({
        tiles: tileIdsOf(req).map((id) => ({ id, label: 'Normal', probability: 0.9 })),
      }),
    });
    const { caseUid, runUid } = await queuedRun({
      generate,
      fewShot: false,
      slide: oneTile,
      callLog: (entry) => logs.push(entry),
    });
    assert.equal(logs.length, 1);
    const entry = logs[0];
    assert.equal(entry.outcome, 'ok');
    assert.equal(entry.attempt, 1);
    assert.equal(entry.batchIndex, 0);
    assert.equal(entry.batches, 1);
    assert.equal(entry.inFlight, 1);
    assert.equal(entry.imageCount, 1);
    assert.equal(entry.model, GEMINI_TEXT_MODEL);
    assert.equal(entry.location, 'global');
    assert.ok(entry.elapsedMs >= 0);
    assert.ok(entry.requestBytes > 0);
    assert.ok(entry.firstCallAfterMs >= 0);
    assert.equal(entry.errorName, undefined);
    assert.equal(entry.status, undefined);
    assert.equal(entry.code, undefined);
    const serialised = JSON.stringify(entry);
    assert.equal(serialised.includes('data:image'), false);
    assert.equal(serialised.includes('Normal'), false);
    assert.equal(serialised.includes('Tumour'), false);
    assert.equal(serialised.includes(caseUid), false);
    assert.equal(serialised.includes(runUid), false);
    assert.equal(serialised.includes('img'), false);
  });

  it('logs a failed tile call with its name, status and code', async () => {
    const logs: PrereadTileCallLog[] = [];
    const generate: GeminiGenerate = async () => {
      const error = new AiError('Stale') as AiError & { status: number; code: string };
      error.status = 429;
      error.code = 'RESOURCE_EXHAUSTED';
      throw error;
    };
    await queuedRun({
      generate,
      fewShot: false,
      slide: oneTile,
      callLog: (entry) => logs.push(entry),
    });
    assert.equal(logs.length, 1);
    assert.equal(logs[0].outcome, 'error');
    assert.equal(logs[0].attempt, 1);
    assert.equal(logs[0].errorName, 'AiError');
    assert.equal(logs[0].status, 429);
    assert.equal(logs[0].code, 'RESOURCE_EXHAUSTED');
    assert.equal(JSON.stringify(logs[0]).includes('Stale'), false);
  });

  it('logs a timed-out tile call once per try', async () => {
    const logs: PrereadTileCallLog[] = [];
    const generate: GeminiGenerate = (req) => hangUntilAbort(req, []);
    await queuedRun({
      generate,
      fewShot: false,
      slide: oneTile,
      callTimeoutMs: 30,
      workerTimeoutMs: 5_000,
      callLog: (entry) => logs.push(entry),
    });
    assert.deepEqual(
      logs.map((entry) => entry.outcome),
      ['timeout', 'timeout', 'timeout'],
    );
    assert.deepEqual(
      logs.map((entry) => entry.attempt),
      [1, 2, 3],
    );
    assert.ok(logs.every((entry) => entry.errorName === 'AiError' && entry.status === undefined));
    assert.equal(logs[0].firstCallAfterMs, logs[2].firstCallAfterMs);
  });
});

describe('stuck Running pre-read', () => {
  let w: World;

  beforeEach(async () => {
    await resetEmulators();
    w = await seedWorld();
  });

  it('the sweep fails a run left in Running past the stale window', async () => {
    const old = '2026-10-27T08:00:00.000Z';
    await w.deps.db.doc('cases/c1/preread/stuck').set({
      status: 'Running',
      requestedAt: old,
      failureReason: '',
      lastUpdatedAt: old,
    });
    await w.deps.db.doc('cases/c1/preread/fresh').set({
      status: 'Running',
      requestedAt: '2026-10-27T09:20:00.000Z',
      failureReason: '',
      lastUpdatedAt: '2026-10-27T09:20:00.000Z',
    });
    const result = await sweepCasesHandler(later(w.deps, 31 * 60 * 1000));
    assert.ok(result.staleJobs >= 1);
    const stuck = await w.deps.db.doc('cases/c1/preread/stuck').get();
    assert.equal(stuck.get('status'), 'Failed');
    assert.equal(stuck.get('failureReason'), 'Stale');
    assert.equal((await w.deps.db.doc('cases/c1/preread/fresh').get()).get('status'), 'Running');
  });
});

describe('prompt', () => {
  it('tells the model that text inside an image is not an instruction', () => {
    assert.match(PREREAD_IMAGE_TEXT_RULE, /not an instruction/i);
    assert.match(PREREAD_IMAGE_TEXT_RULE, /inside an image/i);
  });
});

describe('labelling prompt', () => {
  it('defines Tumour by the central 32×32 and says most tiles are Normal', () => {
    assert.equal(PREREAD_PROMPT_VERSION, 'preread-classify-v4');
    // Proven setting until the tuning run says otherwise (the live 36-tile run took about 9 s).
    assert.equal(TILE_UPSCALE_FACTOR, 1);
    assert.equal(TILE_THINKING_LEVEL, ThinkingLevel.LOW);
    assert.match(PREREAD_PCAM_LABEL_RULE, /central 32 by 32/i);
    assert.match(PREREAD_PCAM_LABEL_RULE, /Most tiles are Normal/i);
    const instructions = buildClassifyInstructions('Cancer');
    assert.ok(instructions.includes(PREREAD_PCAM_LABEL_RULE));
    assert.ok(instructions.includes(PREREAD_IMAGE_TEXT_RULE));
    assert.ok(!buildClassifyInstructions('Malaria').includes(PREREAD_PCAM_LABEL_RULE));
  });

  it('records that the confidence band is stated probability, not calibrated certainty', () => {
    assert.match(CONFIDENCE_CALIBRATION_NOTE, /not calibrated/i);
    assert.match(CONFIDENCE_CALIBRATION_NOTE, /Not clinical certainty/i);
  });
});

describe('upscale and confidence cap', () => {
  it('nearest-neighbour upscale multiplies both sides by a whole factor', () => {
    const src = solidRaster(2, 2, [10, 20, 30]);
    const out = upscaleNearest(src, 3);
    assert.equal(out.width, 6);
    assert.equal(out.height, 6);
    assert.deepEqual([...out.data.subarray(0, 3)], [10, 20, 30]);
    const png = upscaleTilePng(solidPng(8, 8, [1, 2, 3]), 2);
    const decoded = decodeImage(png);
    assert.equal(decoded.width, 16);
    assert.equal(decoded.height, 16);
  });

  it('model-labelled drafts never report High; seed-style drafts stay untouched', () => {
    const tiles: Tile[] = [
      {
        id: 't0',
        imageUid: 'i',
        label: 'Tumour',
        probability: 0.95,
        row: 0,
        col: 0,
        source: 's',
      },
      {
        id: 't1',
        imageUid: 'i',
        label: 'Normal',
        probability: 0.95,
        row: 0,
        col: 1,
        source: 's',
      },
    ];
    const measurements = histologyMeasurements(tiles, { rows: 1, cols: 2, tilePx: 96 }, 0.25);
    const uncapped = histologyDraft(tiles, measurements);
    assert.equal(uncapped.confidenceBand, 'High');
    const capped = applyModelConfidenceCap(uncapped);
    assert.equal(capped.confidenceBand, 'Low');
    assert.ok(capped.confidence <= 0.69);
    // Stored demos use histologyDraft without the cap — still High.
    assert.equal(histologyDraft(tiles, measurements).confidenceBand, 'High');
  });

  it('loads the committed CC0 few-shot fixtures', () => {
    const fixtures = loadFewShotFixtures();
    assert.equal(fixtures.length, 4);
    assert.equal(fixtures.filter((f) => f.label === 'Tumour').length, 2);
    assert.equal(fixtures.filter((f) => f.label === 'Normal').length, 2);
  });
});

describe('parallel batches and thinking level', () => {
  function crop(): TileCrop {
    return { id: 'tile-0', row: 0, col: 0, png: Buffer.from([1]) };
  }
  it('runs up to 4 classify batches at a time', async () => {
    const delayMs = 80;
    let inFlight = 0;
    let maxInFlight = 0;
    const crops: TileCrop[] = Array.from({ length: 36 }, (_, i) => ({
      id: `tile-${i}`,
      row: 0,
      col: i,
      png: Buffer.from([0x89, 0x50, 0x4e, 0x47]),
    }));
    const vision: PrereadVision = {
      async classify(batch) {
        inFlight += 1;
        maxInFlight = Math.max(maxInFlight, inFlight);
        await new Promise((r) => setTimeout(r, delayMs));
        inFlight -= 1;
        return batch.map((c) => ({ id: c.id, label: 'Normal', probability: 0.9 }));
      },
    };
    const started = Date.now();
    const labels = await classifyInBatches(vision, crops, 'Cancer');
    const elapsed = Date.now() - started;
    assert.equal(labels.length, 36);
    assert.equal(labels[0].id, 'tile-0');
    assert.equal(labels[35].id, 'tile-35');
    assert.ok(maxInFlight <= PREREAD_BATCH_CONCURRENCY);
    assert.ok(maxInFlight >= 2, 'batches should overlap');
    // Serial would take one delay per request; four at a time finishes in about a quarter of that.
    const requests = Math.ceil(36 / PREREAD_TILES_PER_REQUEST);
    assert.ok(elapsed < delayMs * requests * 0.5, `expected overlap, got ${elapsed}ms`);
  });

  it('worker budget is 240 s and tiles think at the lowest accepted level', () => {
    assert.equal(TILE_THINKING_LEVEL, ThinkingLevel.LOW);
    assert.equal(PREREAD_WORKER_TIMEOUT_MS, 240_000);
  });

  it('a tile call times out at 25 s and may be tried twice more', () => {
    assert.equal(PREREAD_CALL_TIMEOUT_MS, 25_000);
    assert.equal(PREREAD_TILE_MAX_RETRIES, 2);
  });

  it('OffSchema and Stale are not retried', async () => {
    for (const reason of ['OffSchema', 'Stale'] as const) {
      let calls = 0;
      const vision: PrereadVision = {
        async classify() {
          calls += 1;
          throw new AiError(reason);
        },
      };
      await assert.rejects(
        classifyInBatches(vision, [crop()], 'Cancer', 1, { deadlineMs: Date.now() + 60_000 }),
        (error: unknown) => failureReasonOf(error) === reason,
      );
      assert.equal(calls, 1, reason);
    }
  });

  it('retries stop when the budget cannot fit another try', async () => {
    let calls = 0;
    const vision: PrereadVision = {
      async classify() {
        calls += 1;
        throw new AiError('Timeout');
      },
    };
    await assert.rejects(
      classifyInBatches(vision, [crop()], 'Cancer', 1, {
        // The backoff plus a full tile timeout does not fit in this window.
        deadlineMs: Date.now() + PREREAD_TILE_RETRY_BACKOFF_MS,
        callTimeoutMs: PREREAD_CALL_TIMEOUT_MS,
      }),
      (error: unknown) => failureReasonOf(error) === 'Timeout',
    );
    assert.equal(calls, 1);
  });

  it('httpStatusClass maps status codes without leaking bodies', () => {
    assert.equal(httpStatusClass(200), '2xx');
    assert.equal(httpStatusClass(404), '4xx');
    assert.equal(httpStatusClass(503), '5xx');
    assert.equal(httpStatusClass(undefined), 'none');
  });
});

describe('guarded write, log, seed race', () => {
  let w: World;

  beforeEach(async () => {
    await resetEmulators();
    w = await seedWorld();
  });

  it('logs reason, status class and batch index only on failure', async () => {
    const logs: PrereadFailureLog[] = [];
    const vision: PrereadVision = {
      async classify() {
        const { PrereadCallError } = await import('./preread-worker');
        throw new PrereadCallError('ServiceError', '5xx', null);
      },
    };
    const caseUid = randomUUID();
    const runUid = randomUUID();
    const imagePath = `cases/${caseUid}/slides/slide-0.png`;
    await saveObject(BUCKET, imagePath, solidPng(192, 96, [1, 2, 3]), 'image/png');
    await w.deps.db.collection('cases').doc(caseUid).set({
      uid: caseUid,
      currentStage: 'PrereadQueued',
      prereadRunUid: runUid,
      pathologistUid: w.pathologist.uid,
      participantUids: [w.pathologist.uid],
    });
    await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).set({
      uid: runUid,
      caseUid,
      profile: 'Cancer',
      status: 'Queued',
      imagePaths: [imagePath],
      micronsPerPixel: 0.25,
      segmentationPath: '',
      labelsPath: '',
      labelCounts: {},
      measurements: {},
      draft: {
        findings: [],
        impression: '',
        confidence: 0,
        confidenceBand: '',
        urgency: '',
        nextSteps: [],
      },
      models: {},
      inputLanguage: 'en',
      failureReason: '',
      requestedAt: '2026-11-03T00:00:00.000Z',
      startedAt: '',
      readyAt: '',
      lastUpdatedAt: '2026-11-03T00:00:00.000Z',
    });
    await processQueuedPreread(
      { ...w.deps, bucket: BUCKET },
      caseUid,
      runUid,
      { enabled: true, vision, log: (e) => logs.push(e) },
    );
    assert.equal(logs.length, 1);
    assert.deepEqual(Object.keys(logs[0]).sort(), ['batchIndex', 'reason', 'statusClass']);
    assert.equal(logs[0].reason, 'ServiceError');
    assert.equal(logs[0].statusClass, '5xx');
    assert.equal(typeof logs[0].batchIndex, 'number');
    const serialised = JSON.stringify(logs[0]);
    assert.ok(!serialised.includes('data:image'));
    assert.ok(!serialised.includes('Bearer'));
  });

  it('final write is a no-op once the run is no longer Running', async () => {
    const runRef = w.deps.db.collection('cases').doc('c-guard').collection('preread').doc('r1');
    await runRef.set({ status: 'Ready', failureReason: '', models: { provenance: PROVENANCE } });
    const wrote = await commitIfStillRunning(runRef, {
      status: 'Failed',
      failureReason: 'Timeout',
    });
    assert.equal(wrote, false);
    assert.equal((await runRef.get()).get('status'), 'Ready');
    assert.equal((await runRef.get()).get('failureReason'), '');
  });

  it('tile classify request thinks at the lowest accepted level with a JSON schema', async () => {
    const requests: GeminiGenerateRequest[] = [];
    const generate: GeminiGenerate = async (req) => {
      requests.push(req);
      const parts = (req.contents as { parts: { text?: string }[] }[])[0].parts;
      const ids: string[] = [];
      for (const part of parts) {
        const m = typeof part.text === 'string' ? /tile id=(\S+)/.exec(part.text) : null;
        if (m) ids.push(m[1]);
      }
      return {
        text: JSON.stringify({
          tiles: ids.map((id) => ({ id, label: 'Normal', probability: 0.9 })),
        }),
      };
    };
    const caseUid = randomUUID();
    const runUid = randomUUID();
    const imagePath = `cases/${caseUid}/slides/slide-0.png`;
    await saveObject(BUCKET, imagePath, solidPng(192, 96, [4, 5, 6]), 'image/png');
    await w.deps.db.collection('cases').doc(caseUid).set({
      uid: caseUid,
      currentStage: 'PrereadQueued',
      prereadRunUid: runUid,
      pathologistUid: w.pathologist.uid,
      participantUids: [w.pathologist.uid],
    });
    await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).set({
      uid: runUid,
      caseUid,
      profile: 'Cancer',
      status: 'Queued',
      imagePaths: [imagePath],
      micronsPerPixel: 0.25,
      segmentationPath: '',
      labelsPath: '',
      labelCounts: {},
      measurements: {},
      draft: {
        findings: [],
        impression: '',
        confidence: 0,
        confidenceBand: '',
        urgency: '',
        nextSteps: [],
      },
      models: {},
      inputLanguage: 'en',
      failureReason: '',
      requestedAt: '2026-11-03T00:00:00.000Z',
      startedAt: '',
      readyAt: '',
      lastUpdatedAt: '2026-11-03T00:00:00.000Z',
    });
    await processQueuedPreread(
      { ...w.deps, bucket: BUCKET },
      caseUid,
      runUid,
      { enabled: true, generate, fewShot: false },
    );
    assert.ok(requests.length >= 1);
    assert.equal(requests[0].model, GEMINI_TEXT_MODEL);
    assert.deepEqual(requests[0].config?.thinkingConfig, {
      thinkingLevel: ThinkingLevel.LOW,
    });
    assert.equal(requests[0].config?.responseMimeType, 'application/json');
    assert.ok(requests[0].config?.responseSchema);
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Ready');
  });

  it('seed stored example wins over a concurrent worker', async () => {
    const caseUid = randomUUID();
    const runUid = randomUUID();
    const imagePath = `cases/${caseUid}/slides/slide-0.png`;
    await saveObject(BUCKET, imagePath, solidPng(192, 96, [9, 8, 7]), 'image/png');
    await w.deps.db.collection('cases').doc(caseUid).set({
      uid: caseUid,
      currentStage: 'PrereadQueued',
      prereadRunUid: runUid,
      pathologistUid: w.pathologist.uid,
      participantUids: [w.pathologist.uid],
    });
    const runRef = w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid);
    await runRef.set({
      uid: runUid,
      caseUid,
      profile: 'Cancer',
      status: 'Queued',
      imagePaths: [imagePath],
      micronsPerPixel: 0.25,
      segmentationPath: '',
      labelsPath: '',
      labelCounts: {},
      measurements: {},
      draft: {
        findings: [],
        impression: '',
        confidence: 0,
        confidenceBand: '',
        urgency: '',
        nextSteps: [],
      },
      models: {},
      inputLanguage: 'en',
      failureReason: '',
      requestedAt: '2026-11-03T00:00:00.000Z',
      startedAt: '',
      readyAt: '',
      lastUpdatedAt: '2026-11-03T00:00:00.000Z',
    });

    const releaseClassify = new Promise<void>((resolve) => {
      // Open the classify gate after the seed transaction has committed.
      setTimeout(resolve, 120);
    });
    const vision: PrereadVision = {
      async classify(crops) {
        await releaseClassify;
        return crops.map((c) => ({ id: c.id, label: 'Tumour', probability: 0.99 }));
      },
    };

    const worker = processQueuedPreread(
      { ...w.deps, bucket: BUCKET },
      caseUid,
      runUid,
      { enabled: true, vision },
    );

    // Wait until the worker has claimed Running, then write the stored example.
    for (let i = 0; i < 40; i++) {
      const status = (await runRef.get()).get('status');
      if (status === 'Running') break;
      await new Promise((r) => setTimeout(r, 10));
    }
    assert.equal((await runRef.get()).get('status'), 'Running');

    const storedDraft = {
      findings: [{ text: 'Stored demo finding.', evidenceIds: [] as string[] }],
      impression: 'Stored demo impression.',
      confidence: 0.5,
      confidenceBand: 'Moderate',
      urgency: 'Routine',
      nextSteps: ['Review.'],
    };
    await runRef.firestore.runTransaction(async (tx) => {
      const snap = await tx.get(runRef);
      const status = String(snap.get('status') ?? '');
      if (status !== 'Queued' && status !== 'Running') return;
      tx.update(runRef, {
        status: 'Ready',
        failureReason: '',
        draft: storedDraft,
        measurements: { tumourTiles: 0, normalTiles: 2, tumourAreaPercent: 0, largestFocusMm: 0 },
        models: { provenance: PROVENANCE },
        readyAt: '2026-11-03T00:01:00.000Z',
        lastUpdatedAt: '2026-11-03T00:01:00.000Z',
      });
    });

    await worker;
    const final = (await runRef.get()).data();
    assert.equal(final?.status, 'Ready');
    assert.equal(final?.models?.provenance, PROVENANCE);
    assert.equal(final?.draft?.impression, 'Stored demo impression.');
    assert.equal(final?.failureReason, '');
  });
});

describe('few-shot classify request', () => {
  const crop = (id: string): TileCrop => ({
    id,
    row: 0,
    col: 0,
    png: Buffer.from(`png-${id}`),
  });

  it('prepends the four labelled fixtures before case tiles', () => {
    const fixtures = loadFewShotFixtures();
    assert.equal(fixtures.length, 4);
    const crops = [crop('case-a'), crop('case-b')];
    const content = buildClassifyUserContent(crops, fixtures);
    const texts = content.filter((p) => p.text !== undefined).map((p) => p.text as string);
    assert.ok(texts[0]?.includes('calibration only'));
    assert.equal(texts[1], `example label=${fixtures[0].label} id=${fixtures[0].id}`);
    assert.equal(texts[2], `example label=${fixtures[1].label} id=${fixtures[1].id}`);
    assert.equal(texts[3], `example label=${fixtures[2].label} id=${fixtures[2].id}`);
    assert.equal(texts[4], `example label=${fixtures[3].label} id=${fixtures[3].id}`);
    assert.ok(texts[5]?.startsWith('Classify these 2 tiles.'));
    assert.equal(countClassifyImages(content), 6);
    const built = buildClassifyRequestBody({
      model: GEMINI_TEXT_MODEL,
      crops: crops.slice(0, PREREAD_TILES_PER_REQUEST),
      profile: 'Cancer',
      fewShot: fixtures,
    });
    assert.ok(String(built.body.config?.systemInstruction).includes(PREREAD_FEW_SHOT_INSTRUCTION));
    assert.equal(built.body.model, GEMINI_TEXT_MODEL);
    assert.equal(built.body.config?.responseMimeType, 'application/json');
    assert.ok(built.body.config?.responseSchema);
  });

  it('with no few-shot holds case tiles only', () => {
    const crops = [crop('t0'), crop('t1')];
    const expected: unknown[] = [
      {
        text: `Classify these ${crops.length} tiles. ids=${JSON.stringify(crops.map((c) => c.id))}`,
      },
      { text: 'tile id=t0' },
      { inlineData: { mimeType: 'image/png', data: crops[0].png.toString('base64') } },
      { text: 'tile id=t1' },
      { inlineData: { mimeType: 'image/png', data: crops[1].png.toString('base64') } },
    ];
    assert.equal(
      JSON.stringify(buildClassifyUserContent(crops, [])),
      JSON.stringify(expected),
    );
    const built = buildClassifyRequestBody({
      model: GEMINI_TEXT_MODEL,
      crops: crops.slice(0, PREREAD_TILES_PER_REQUEST),
      profile: 'Cancer',
      fewShot: [],
    });
    assert.equal(built.body.config?.systemInstruction, buildClassifyInstructions('Cancer'));
    assert.equal(built.exampleIds.size, 0);
  });

  it('refuses an output row whose id is an example id', () => {
    const exampleIds = new Set(['train-1', 'train-2']);
    assert.throws(
      () =>
        parseClassifyTiles(
          [
            { id: 'case-a', label: 'Normal', probability: 0.9 },
            { id: 'train-1', label: 'Tumour', probability: 0.99 },
          ],
          { exampleIds },
        ),
      (e: unknown) => e instanceof PrereadCallError && e.reason === 'OffSchema',
    );
  });

  it('keeps image count under the per-request cap with a tile plus four examples', () => {
    const fixtures = loadFewShotFixtures();
    const crops = Array.from({ length: PREREAD_TILES_PER_REQUEST }, (_, i) => crop(`c${i}`));
    const content = buildClassifyUserContent(crops, fixtures);
    const images = countClassifyImages(content);
    assert.equal(images, PREREAD_TILES_PER_REQUEST + fixtures.length);
    assert.ok(images <= PREREAD_MAX_IMAGES_PER_REQUEST);
    assert.doesNotThrow(() =>
      buildClassifyRequestBody({ model: GEMINI_TEXT_MODEL, crops, profile: 'Cancer', fewShot: fixtures }),
    );
  });

  it('rejects more than one case tile per request even without examples', () => {
    const crops = Array.from({ length: PREREAD_TILES_PER_REQUEST + 1 }, (_, i) => crop(`c${i}`));
    assert.throws(
      () =>
        buildClassifyRequestBody({ model: GEMINI_TEXT_MODEL, crops, profile: 'Cancer', fewShot: [] }),
      (e: unknown) => e instanceof PrereadCallError && e.reason === 'OffSchema',
    );
  });

  it('gemini classify request carries fixtures when few-shot is on', async () => {
    await resetEmulators();
    const w = await seedWorld();
    const fixtures = loadFewShotFixtures();
    assert.ok(fixtures.length >= 4);
    const requests: GeminiGenerateRequest[] = [];
    const generate: GeminiGenerate = async (req) => {
      requests.push(req);
      const parts = (req.contents as { parts: { text?: string }[] }[])[0].parts;
      const ids: string[] = [];
      for (const part of parts) {
        const m = typeof part.text === 'string' ? /tile id=(\S+)/.exec(part.text) : null;
        if (m) ids.push(m[1]);
      }
      return {
        text: JSON.stringify({
          tiles: ids.map((id) => ({ id, label: 'Normal', probability: 0.9 })),
        }),
      };
    };
    const caseUid = randomUUID();
    const runUid = randomUUID();
    const imagePath = `cases/${caseUid}/slides/slide-0.png`;
    await saveObject(BUCKET, imagePath, solidPng(192, 96, [4, 5, 6]), 'image/png');
    await w.deps.db.collection('cases').doc(caseUid).set({
      uid: caseUid,
      currentStage: 'PrereadQueued',
      prereadRunUid: runUid,
      pathologistUid: w.pathologist.uid,
      participantUids: [w.pathologist.uid],
    });
    await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).set({
      uid: runUid,
      caseUid,
      profile: 'Cancer',
      status: 'Queued',
      imagePaths: [imagePath],
      micronsPerPixel: 0.25,
      segmentationPath: '',
      labelsPath: '',
      labelCounts: {},
      measurements: {},
      draft: {
        findings: [],
        impression: '',
        confidence: 0,
        confidenceBand: '',
        urgency: '',
        nextSteps: [],
      },
      models: {},
      inputLanguage: 'en',
      failureReason: '',
      requestedAt: '2026-11-04T00:00:00.000Z',
      startedAt: '',
      readyAt: '',
      lastUpdatedAt: '2026-11-04T00:00:00.000Z',
    });
    await processQueuedPreread(
      { ...w.deps, bucket: BUCKET },
      caseUid,
      runUid,
      { enabled: true, generate, fewShot: fixtures },
    );
    assert.ok(requests.length >= 1);
    const req = requests[0];
    assert.equal(req.model, GEMINI_TEXT_MODEL);
    assert.ok(String(req.config?.systemInstruction).includes(PREREAD_FEW_SHOT_INSTRUCTION));
    const parts = (req.contents as { parts: { text?: string; inlineData?: unknown }[] }[])[0].parts;
    const texts = parts.filter((c) => c.text !== undefined).map((c) => c.text as string);
    assert.ok(texts[0]?.includes('calibration only'));
    assert.ok(
      texts.some((t) => t.includes(`example label=${fixtures[0].label} id=${fixtures[0].id}`)),
    );
    assert.ok(parts.filter((c) => c.inlineData !== undefined).length >= 5);
    const run = (
      await w.deps.db.collection('cases').doc(caseUid).collection('preread').doc(runUid).get()
    ).data();
    assert.equal(run?.status, 'Ready');
  });
});

