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
    const ids = sceneEdgeIds();
    for (let i = 0; i < ids.length; i++) {
      api.removeEdge(ids[i]);
    }
    trigger = '';
    applyStep(0);
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
    // Only complete if this step uses pulse sequences
    if (step.run && step.run.some(e => e.type === 'pulseSequence')) {
      completeCurrentStep();
    }
  }
}

// Node-driven start: the Buy button or the schedule icon in PersonNode
function startBuy(kind) {
  if (stepIndex !== 0 || running) return;
  trigger = kind;
  const scheduled = kind === 'scheduled';
  const label = scheduled ? 'schedule fires: buy' : 'buy';
  buttonEnabled = false;
  running = true;
  const api = window.__reactFlowCanvasApi;
  api.addEdge('e-you-agent', 'person', 'person-agent',
    scheduled ? 'right-bottom' : 'right-top',
    scheduled ? 'left-bottom' : 'left-top', label);
  api.pulseEdge(label, pulseDuration);
}

// --- Step declarations ---

// Edges this scene adds; restart removes them
function sceneEdgeIds() {
  return ['e-you-agent', 'e-agent-home', 'e-home-agent', 'e-agent-svc', 'e-svc-home', 'e-svc-agent',
    'e-agent-signin', 'e-signin-agent', 'e-agent-you', 'e-you-signin', 'e-signin-pass'];
}

function notifyLabel() {
  return trigger === 'scheduled' ? 'notification: approve · HBHK-S3ZN' : 'approve here · HBHK-S3ZN';
}

function getProcessFlowSteps() {
  return [
    {
      id: 'trigger',
      title: '1',
      message: 'You buy something, or a schedule does it for you',
      actionLabel: '',
      actionEnabled: false,
      phase: 0,
      completeAfterMs: pulseDuration,
      // Started by startBuy() from PersonNode, not by the control button
    },
    {
      id: 'ask',
      title: '2',
      message: 'Your agent needs to call the store, so it first asks its home for an ID card',
      actionLabel: 'Ask',
      phase: 1,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-agent-home', source: 'person-agent', target: 'agreements', sourceHandle: 'top-left', targetHandle: 'bottom-left', label: 'asks for ID card' },
        { type: 'pulse', edge: 'asks for ID card', durationMs: pulseDuration },
      ],
    },
    {
      id: 'issue',
      title: '3',
      message: 'Its home issues the ID card',
      actionLabel: 'Issue',
      phase: 2,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-home-agent', source: 'agreements', target: 'person-agent', sourceHandle: 'bottom-right', targetHandle: 'top-right', label: 'issues ID card' },
        { type: 'pulse', edge: 'issues ID card', durationMs: pulseDuration },
      ],
    },
    {
      id: 'request',
      title: '4',
      message: 'Your agent sends the buy request, signed, with its ID card',
      actionLabel: 'Send',
      phase: 3,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-agent-svc', source: 'person-agent', target: 'entity-agent', sourceHandle: 'right-top', targetHandle: 'left-top', label: 'buy request + ID card' },
        { type: 'pulse', edge: 'buy request + ID card', durationMs: pulseDuration },
      ],
    },
    {
      id: 'check',
      title: '5',
      message: "The store checks the card against the home's published key",
      actionLabel: 'Check',
      phase: 4,
      completeAfterRoundTrip: true,
      run: [
        { type: 'addEdge', id: 'e-svc-home', source: 'entity-agent', target: 'agreements', sourceHandle: 'top-left', targetHandle: 'right-bottom', label: 'checks card' },
        { type: 'pulseRoundTrip', edge: 'checks card', durationMs: pulseDuration },
      ],
    },
    {
      id: 'answer',
      title: '6',
      message: "The store knows which agent this is, but not who it's buying for",
      actionLabel: 'Answer',
      phase: 5,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-svc-agent', source: 'entity-agent', target: 'person-agent', sourceHandle: 'left-bottom', targetHandle: 'right-bottom', label: '401 · who for?' },
        { type: 'pulse', edge: '401 · who for?', durationMs: pulseDuration },
      ],
    },
    // --- Scene 2: who is your agent working for? (walkthrough-2 round A) ---
    {
      id: 'signin',
      title: '7',
      message: 'The store needs to know who your agent works for, so your agent turns to your sign-in',
      actionLabel: 'Continue',
      phase: 6,
      runningPhase: 6.5,
      completeAfterMs: pulseDuration,
      // Your sign-in joins the canvas at phase >= 6.5 (getNodes)
    },
    {
      id: 'vouch',
      title: '8',
      message: 'Your agent asks your sign-in to vouch for its person, for this store',
      actionLabel: 'Ask',
      phase: 7,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-agent-signin', source: 'person-agent', target: 'entity', sourceHandle: 'bottom-left', targetHandle: 'top-left', label: 'vouch for my person?' },
        { type: 'pulse', edge: 'vouch for my person?', durationMs: pulseDuration },
      ],
    },
    {
      id: 'reply',
      title: '9',
      message: 'Your sign-in says a person must approve, and hands back a code',
      actionLabel: 'Reply',
      phase: 8,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-signin-agent', source: 'entity', target: 'person-agent', sourceHandle: 'top-right', targetHandle: 'bottom-right', label: '202 · approve · HBHK-S3ZN' },
        { type: 'pulse', edge: '202 · approve · HBHK-S3ZN', durationMs: pulseDuration },
      ],
    },
    {
      id: 'notify',
      title: '10',
      message: trigger === 'scheduled'
        ? 'Nobody is at the keyboard, so your agent sends you a link to approve within 10 minutes'
        : 'Your agent shows you where to approve',
      actionLabel: 'Notify',
      phase: 9,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-agent-you', source: 'person-agent', target: 'person', sourceHandle: 'left-bottom', targetHandle: 'bottom-right', label: notifyLabel() },
        { type: 'pulse', edge: notifyLabel(), durationMs: pulseDuration },
      ],
    },
    {
      id: 'confirm',
      title: '11',
      message: 'You sign in as usual (Microsoft here) and confirm this agent',
      actionLabel: 'Confirm',
      phase: 10,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-you-signin', source: 'person', target: 'entity', sourceHandle: 'bottom-left', targetHandle: 'left-top', label: 'sign in + Confirm' },
        { type: 'pulse', edge: 'sign in + Confirm', durationMs: pulseDuration },
      ],
    },
    {
      id: 'pass',
      title: '12',
      message: 'Your sign-in issues a pass: you approved this agent, for this store',
      actionLabel: 'Issue',
      phase: 11,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-signin-pass', source: 'entity', target: 'person-agent', sourceHandle: 'right-top', targetHandle: 'bottom-right', label: 'pass (person token)' },
        { type: 'pulse', edge: 'pass (person token)', durationMs: pulseDuration },
      ],
    },
    {
      id: 'done',
      title: '',
      message: 'Now your agent can show who it works for. Next: the store asks to see your profile.',
      actionLabel: 'Start over',
      phase: 12,
      restartOnAction: true,
    },
  ];
}

// --- Node & edge builders ---

// Saving the layout writes only the nodes on the canvas, so a node hidden at save
// time (e.g. Your sign-in during scene 1) can be missing from layout.json.
function makeNode(id, label, extra) {
  const n = layout.nodes[id] || { x: 336, y: 600, width: 360, height: 230 };
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
    makeNode("person", "You"),
    makeNode("person-agent", "Your agent"),
    makeNode("agreements", "Agent's home"),
    makeNode("entity-agent", "Service"),
    makeNode("control", "Control", { chrome: false }),
  ].concat(phase >= 6.5 ? [makeNode("entity", "Your sign-in")] : []);
}

function getEdges() {
  return [];
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
