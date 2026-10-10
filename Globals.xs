// --- Step machine runtime ---

function applyStep(index) {
  const steps = getProcessFlowSteps();
  const step = steps[index];
  stepIndex = index;
  phase = step.phase;
  phaseLabel = step.title;
  phaseMessage = step.message;
  buttonLabel = step.actionLabel || '';
  buttonEnabled = step.actionEnabled !== false;

  // Run onEnter callback if defined
  if (step.onEnter) {
    step.onEnter();
  }
}

function nextStep() {
  const steps = getProcessFlowSteps();
  const step = steps[stepIndex];

  if (step.restartOnAction) {
    const api = window.__reactFlowCanvasApi;
    api.clearPulse();
    // Remove accumulated signed edges
    for (let i = 1; i <= acceptedCount; i++) {
      api.removeEdge('e-signed-' + i);
    }
    offeredTerm = '';
    agreementDecision = '';
    acceptedCount = 0;
    kleindorfersTerms = [
      { terms: 'SD-BASE', policy: 'Accept' },
      { terms: 'SD-BY-DP', policy: 'Reject' },
    ];
    // Restart goes to step 1 (lookup), not step 0 (delegate) on subsequent runs
    applyStep(hasDelegated ? 1 : 0);
    return;
  }

  phase = step.runningPhase || step.phase;
  buttonEnabled = false;
  running = true;

  const api = window.__reactFlowCanvasApi;
  if (api) {
    const effects = step.run || [];
    for (let i = 0; i < effects.length; i++) {
      const effect = effects[i];
      if (effect.type === 'pulse' && effect.edge) {
        api.pulseEdge(effect.edge, effect.durationMs || pulseDuration);
      } else if (effect.type === 'pulseRoundTrip' && effect.edge) {
        api.pulseEdgeRoundTrip(effect.edge, effect.durationMs || pulseDuration);
      } else if (effect.type === 'clearPulse') {
        api.clearPulse();
      } else if (effect.type === 'addEdge') {
        api.addEdge(effect.id, effect.source, effect.target,
          effect.sourceHandle, effect.targetHandle, effect.label,
          effect.noArrow, effect.data);
      } else if (effect.type === 'removeEdge') {
        api.removeEdge(effect.edgeId);
      } else if (effect.type === 'pulseSequence' && effect.edges) {
        pulse = { active: true, edges: effect.edges, step: 0, currentEdge: '' };
      }
    }
  }

  // Mark first delegation
  if (step.id === 'delegate') {
    hasDelegated = true;
  }
}

function completeCurrentStep() {
  running = false;
  const steps = getProcessFlowSteps();
  const step = steps[stepIndex];

  // Run cleanup effects
  const api = window.__reactFlowCanvasApi;
  if (api && step.cleanup) {
    for (let i = 0; i < step.cleanup.length; i++) {
      const effect = step.cleanup[i];
      if (effect.type === 'removeEdge') {
        api.removeEdge(effect.edgeId);
      }
    }
  }

  // Run onComplete callback if defined
  if (step.onComplete) {
    step.onComplete();
  }

  const nextIndex = resolveNextStep(step, stepIndex);
  applyStep(nextIndex);
}

function resolveNextStep(step, currentIndex) {
  const steps = getProcessFlowSteps();
  // Conditional branching
  if (step.nextIf) {
    for (let i = 0; i < step.nextIf.length; i++) {
      const branch = step.nextIf[i];
      if (branch.when()) {
        return findStepIndex(branch.goto);
      }
    }
  }
  if (typeof step.next === 'number') {
    return step.next;
  }
  if (typeof step.next === 'string') {
    return findStepIndex(step.next);
  }
  return Math.min(currentIndex + 1, steps.length - 1);
}

function findStepIndex(id) {
  const steps = getProcessFlowSteps();
  for (let i = 0; i < steps.length; i++) {
    if (steps[i].id === id) return i;
  }
  return 0;
}

// --- Completion triggers ---
// These are called from Timers/ChangeListeners in the page markup

function onTimerComplete() {
  if (running) {
    completeCurrentStep();
  }
}

function onRoundTripTimerComplete() {
  if (running) {
    completeCurrentStep();
  }
}

function onPulseSequenceComplete() {
  if (running && !pulse.active) {
    const step = getProcessFlowSteps()[stepIndex];
    // Only complete if this step uses pulse sequences (send, proffer)
    if (step.id === 'send' || (step.run && step.run.some(e => e.type === 'pulseSequence'))) {
      completeCurrentStep();
    }
  }
}

function onTermSelected() {
  if (offeredTerm !== '' && phase === 3) {
    // Node-driven step advance: user chose a term
    stepIndex = findStepIndex('send');
    sendTermEffects();
    running = true;
  }
}

function sendTermEffects() {
  phase = 'sending';
  buttonEnabled = false;
  const api = window.__reactFlowCanvasApi;
  api.addEdge('e-p-pa-send', 'person', 'person-agent', 'bottom-right', 'top-right', 'send', false, { labelPosition: 60 });
  pulse = { active: true, edges: ['send'], step: 0, currentEdge: 'lookup' };
}

// --- Domain helpers ---

function responsive(small, large) {
  return mediaSize.sizeIndex <= 2 ? small : large;
}

function makeStoreEntry(term, counterparty) {
  return {
    term: term,
    counterparty: counterparty,
    timestamp: new Date().toISOString(),
    country: "USA",
  };
}

function lookupTermPolicy(term) {
  for (let i = 0; i < kleindorfersTerms.length; i++) {
    if (kleindorfersTerms[i].terms === term) return kleindorfersTerms[i].policy;
  }
  return "Reject";
}

function onPulseEdgeChange(change) {
  if (change.newValue === "proffers" && offeredTerm !== "") {
    agreementDecision =
      kleindorfersTerms.find(t => t.terms === offeredTerm) &&
      kleindorfersTerms.find(t => t.terms === offeredTerm).policy === "Accept"
        ? "yes"
        : "no";
  }
}

function stepLabel(n) {
  return String(n - (hasDelegated ? 1 : 0));
}

// --- Step declarations ---

function getProcessFlowSteps() {
  return [
    {
      id: 'delegate',
      title: '1',
      message: "Alice and Kleindorfer's delegate agency",
      actionLabel: 'Delegate',
      phase: 0,
      runningPhase: 'delegating',
      completeAfterMs: pulseDuration,
      run: [
        { type: 'clearPulse' },
        { type: 'pulse', edge: 'delegates agency', durationMs: pulseDuration },
        { type: 'pulse', edge: 'delegates personal agency', durationMs: pulseDuration },
      ],
      onEnter: () => {
        offeredTerm = '';
        agreementDecision = '';
        acceptedCount = 0;
        kleindorfersTerms = [
          { terms: 'SD-BASE', policy: 'Accept' },
          { terms: 'SD-BY-DP', policy: 'Reject' },
        ];
      },
    },
    {
      id: 'lookup',
      title: stepLabel(2),
      message: 'Alice looks up terms',
      actionLabel: 'Lookup',
      phase: 1,
      runningPhase: 2,
      completeAfterRoundTrip: true,
      run: [
        { type: 'addEdge', id: 'e-p-ag', source: 'person', target: 'agreements', sourceHandle: 'right-top', targetHandle: 'left-top', label: 'lookup' },
        { type: 'pulseRoundTrip', edge: 'lookup', durationMs: pulseDuration },
      ],
      cleanup: [
        { type: 'removeEdge', edgeId: 'e-p-ag' },
      ],
    },
    {
      id: 'choose-term',
      title: stepLabel(3),
      message: "Choose a term from Alice's list",
      actionLabel: '',
      phase: 3,
      actionEnabled: false,
      // Completion is driven by onTermSelected() via ChangeListener on offeredTerm
    },
    {
      id: 'send',
      title: stepLabel(3),
      message: "Sending term to Alice's agent",
      phase: 'sending',
      actionLabel: '',
      actionEnabled: false,
      cleanup: [
        { type: 'removeEdge', edgeId: 'e-p-pa-send' },
      ],
      // Completion driven by pulse sequence finishing (ChangeListener on pulse.active)
    },
    {
      id: 'proffer',
      title: stepLabel(4),
      message: "Alice's agent proffers agreement",
      actionLabel: 'Proffer',
      phase: 4,
      runningPhase: 'proffering',
      // Completion driven by pulse sequence finishing (ChangeListener on pulse.active)
      run: [
        { type: 'pulseSequence', edges: ['proffers'] },
      ],
    },
    {
      id: 'consult',
      title: stepLabel(5),
      message: "Kleindorfer's agent consults policy",
      actionLabel: 'Consult Policy',
      phase: 5,
      runningPhase: 'consulting',
      completeAfterRoundTrip: true,
      run: [
        { type: 'addEdge', id: 'e-ea-consult', source: 'entity-agent', target: 'entity', sourceHandle: 'bottom-left', targetHandle: 'top-left', label: 'consults policy' },
        { type: 'pulseRoundTrip', edge: 'consults policy', durationMs: pulseDuration },
      ],
      cleanup: [
        { type: 'removeEdge', edgeId: 'e-ea-consult' },
      ],
      nextIf: [
        { when: () => agreementDecision === 'yes', goto: 'done' },
        { when: () => agreementDecision === 'no', goto: 'rejected' },
      ],
      onComplete: () => {
        const status = agreementDecision === 'yes' ? 'accepted' : 'rejected';
        alicePersonalDataStore = [...alicePersonalDataStore, makeStoreEntry(offeredTerm + ' (' + status + ')', "Kleindorfer's")];
        kleindorfersOrgDataStore = [...kleindorfersOrgDataStore, makeStoreEntry(offeredTerm + ' (' + status + ')', 'Alice')];
        if (agreementDecision === 'yes') {
          acceptedCount = acceptedCount + 1;
          window.__reactFlowCanvasApi.addEdge('e-signed-' + acceptedCount, 'person', 'entity-agent', 'right-magnet', 'left-magnet', 'signed: ' + offeredTerm + ' \u2282\u2283', true);
        }
      },
    },
    {
      id: 'rejected',
      title: stepLabel(6),
      message: 'Agreement rejected',
      actionLabel: 'Start Over',
      phase: 7,
      restartOnAction: true,
    },
    {
      id: 'done',
      title: stepLabel(6),
      message: agreementDecision === 'yes' ? 'Agreement signed and posted to ledger' : 'Agreement rejected',
      actionLabel: 'Start Over',
      phase: 7,
      restartOnAction: true,
    },
  ];
}

// --- Node & edge builders ---

function makeNode(id, label, extra) {
  const n = layout.nodes[id];
  const data = { label: label };
  if (extra) {
    for (const k in extra) {
      data[k] = extra[k];
    }
  }
  return { id: id, position: { x: n.x, y: n.y }, data: data, width: n.width, height: n.height };
}

function getNodes() {
  return [
    makeNode("person", "You", { magnetY: "12%" }),
    makeNode("person-agent", "Your agent"),
    makeNode("agreements", "Agent's home"),
    makeNode("entity-agent", "Service", { magnetY: "22%" }),
    makeNode("entity", "Your sign-in"),
    makeNode("control", "Control", { chrome: false }),
  ];
}

function getEdges() {
  return [
    {
      id: "e-p-pa",
      source: "person",
      target: "person-agent",
      sourceHandle: "bottom-left",
      targetHandle: "top-left",
      data: { label: "delegates personal agency", labelPosition: 40 },
    },
    {
      id: "e-pa-ea",
      source: "person-agent",
      target: "entity-agent",
      sourceHandle: "right-top",
      targetHandle: "left-bottom",
      data: { label: "proffers" },
    },
    {
      id: "e-ea-e",
      source: "entity",
      target: "entity-agent",
      sourceHandle: "top-right",
      targetHandle: "bottom-right",
      data: { label: "delegates agency", labelPosition: 30 },
    },
  ];
}

function saveLayout() {
  const json = JSON.stringify(window.__reactFlowCanvasApi.getLayout(), null, 2);
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'layout.json';
  a.click();
  URL.revokeObjectURL(url);
}
