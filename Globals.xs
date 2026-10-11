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

// Draws step 1's arrow (You -> Your agent) for the given path; returns its label
function addTriggerEdge(kind) {
  const scheduled = kind === 'scheduled';
  const label = scheduled ? '1. schedule fires: buy' : '1. buy';
  window.__reactFlowCanvasApi.addEdge('e-you-agent', 'person', 'person-agent',
    scheduled ? 'right-bottom' : 'right-top',
    scheduled ? 'left-bottom' : 'left-top', label);
  return label;
}

// Node-driven start: the Buy button or the schedule icon in PersonNode
function startBuy(kind) {
  if (stepIndex !== 0 || running) return;
  trigger = kind;
  buttonEnabled = false;
  running = true;
  const label = addTriggerEdge(kind);
  window.__reactFlowCanvasApi.pulseEdge(label, pulseDuration);
}

// --- Step URL: ?step=N[&path=scheduled] ---

// Query string for the current step (written to the URL by ReactFlowPage).
// A string, because the vendored XMLUI 0.12.15 navigate() ignores the
// { queryParams, replace } options that 0.14 documents.
function stepQueryString() {
  const steps = getProcessFlowSteps();
  const step = steps[stepIndex];
  return 'step=' + (step.title || 'end') + (trigger === 'scheduled' ? '&path=scheduled' : '');
}

// The same string for a step and path read from the URL, for comparison
function urlStepString(step, path) {
  return 'step=' + step + (path === 'scheduled' ? '&path=scheduled' : '');
}

// Arrive at step n (1-based, or 'end') with every earlier step already done:
// earlier arrows drawn without pulsing; phase gates reveal the node contents
function jumpToStep(n, path) {
  const kind = path === 'scheduled' ? 'scheduled' : 'interactive';
  const steps = getProcessFlowSteps();
  const target = n === 'end' ? steps.length - 1 : Math.min(Math.max(Number(n) - 1, 0), steps.length - 1);
  if (!(target >= 0)) return;
  const api = window.__reactFlowCanvasApi;
  api.clearPulse();
  const ids = sceneEdgeIds();
  for (let i = 0; i < ids.length; i++) {
    api.removeEdge(ids[i]);
  }
  running = false;
  if (target === 0) {
    // step=1: back to the start, nothing drawn yet
    trigger = '';
    applyStep(0);
    return;
  }
  trigger = kind;
  addTriggerEdge(kind);
  for (let i = 1; i < target; i++) {
    const effects = steps[i].run || [];
    for (let j = 0; j < effects.length; j++) {
      const e = effects[j];
      if (e.type === 'addEdge') {
        const label = e.id === 'e-agent-you' ? notifyLabelFor(kind) : e.label;
        api.addEdge(e.id, e.source, e.target, e.sourceHandle, e.targetHandle, label, e.noArrow, e.data);
      }
    }
  }
  running = false;
  pulse = { active: false, edges: [], step: -1, currentEdge: '' };
  applyStep(target);
}

// --- Step declarations ---

// Edges this scene adds; restart removes them
function sceneEdgeIds() {
  return ['e-you-agent', 'e-agent-home', 'e-home-agent', 'e-agent-svc', 'e-svc-home', 'e-svc-agent',
    'e-agent-signin', 'e-signin-agent', 'e-agent-you', 'e-you-signin', 'e-signin-pass'];
}

function notifyLabel() {
  return notifyLabelFor(trigger);
}

function notifyLabelFor(kind) {
  return kind === 'scheduled' ? '9. notification: approve · HBHK-S3ZN' : '9. approve here · HBHK-S3ZN';
}

function getProcessFlowSteps() {
  return [
    {
      id: 'trigger',
      title: '1',
      message: 'The Person (you) buys something, or a schedule does it (click Buy to start)',
      actionLabel: '',
      actionEnabled: false,
      phase: 0,
      completeAfterMs: pulseDuration,
      // Started by startBuy() from PersonNode, not by the control button
    },
    {
      id: 'ask',
      title: '2',
      message: 'The Agent (your assistant) needs to call the Resource (the store), so it first asks its Agent Provider (the agent\'s home) for an agent token (its signed ID)',
      actionLabel: 'Ask',
      phase: 1,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-agent-home', source: 'person-agent', target: 'agreements', sourceHandle: 'top-left', targetHandle: 'bottom-left', label: '2. asks for agent token' },
        { type: 'pulse', edge: '2. asks for agent token', durationMs: pulseDuration },
      ],
    },
    {
      id: 'issue',
      title: '3',
      message: 'The Agent Provider issues the agent token (who the agent is, signed by its provider)',
      actionLabel: 'Issue',
      phase: 2,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-home-agent', source: 'agreements', target: 'person-agent', sourceHandle: 'bottom-right', targetHandle: 'top-right', label: '3. issues agent token' },
        { type: 'pulse', edge: '3. issues agent token', durationMs: pulseDuration },
      ],
    },
    {
      id: 'request',
      title: '4',
      message: 'The Agent sends the buy request to the Resource, signed, with its agent token',
      actionLabel: 'Send',
      phase: 3,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-agent-svc', source: 'person-agent', target: 'entity-agent', sourceHandle: 'right-top', targetHandle: 'left-top', label: '4. buy request + agent token' },
        { type: 'pulse', edge: '4. buy request + agent token', durationMs: pulseDuration },
      ],
    },
    {
      id: 'check',
      title: '5',
      message: "The Resource checks the agent token against the Agent Provider's published key",
      actionLabel: 'Check',
      phase: 4,
      completeAfterRoundTrip: true,
      run: [
        { type: 'addEdge', id: 'e-svc-home', source: 'entity-agent', target: 'agreements', sourceHandle: 'top-left', targetHandle: 'right-bottom', label: '5. checks agent token' },
        { type: 'pulseRoundTrip', edge: '5. checks agent token', durationMs: pulseDuration },
      ],
    },
    {
      id: 'answer',
      title: '6',
      message: "The Resource knows which agent this is, but not who it's buying for",
      actionLabel: 'Answer',
      phase: 5,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-svc-agent', source: 'entity-agent', target: 'person-agent', sourceHandle: 'left-bottom', targetHandle: 'right-bottom', label: '6. 401 · who for?' },
        { type: 'pulse', edge: '6. 401 · who for?', durationMs: pulseDuration },
      ],
    },
    // --- Scene 2: who is your agent working for? (walkthrough-2 round A) ---
    {
      id: 'vouch',
      title: '7',
      message: 'The Resource needs to know who the Agent works for, so the Agent asks its Person Server (your sign-in) to vouch for its Person',
      actionLabel: 'Ask',
      phase: 6,
      runningPhase: 6.5,
      completeAfterMs: pulseDuration,
      // Your sign-in's "not involved yet" line clears at phase >= 6.5 (EntityNode)
      run: [
        { type: 'addEdge', id: 'e-agent-signin', source: 'person-agent', target: 'entity', sourceHandle: 'bottom-left', targetHandle: 'top-left', label: '7. requests person token' },
        { type: 'pulse', edge: '7. requests person token', durationMs: pulseDuration },
      ],
    },
    {
      id: 'reply',
      title: '8',
      message: 'The Person Server says the Person must approve, and hands back a code',
      actionLabel: 'Reply',
      phase: 7,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-signin-agent', source: 'entity', target: 'person-agent', sourceHandle: 'top-right', targetHandle: 'bottom-right', label: '8. 202 · approve · HBHK-S3ZN' },
        { type: 'pulse', edge: '8. 202 · approve · HBHK-S3ZN', durationMs: pulseDuration },
      ],
    },
    {
      id: 'notify',
      title: '9',
      message: trigger === 'scheduled'
        ? 'Nobody is at the keyboard, so the Agent sends the Person a link to approve within 10 minutes'
        : 'The Agent shows the Person where to approve',
      actionLabel: 'Notify',
      phase: 8,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-agent-you', source: 'person-agent', target: 'person', sourceHandle: 'left-bottom', targetHandle: 'bottom-right', label: notifyLabel() },
        { type: 'pulse', edge: notifyLabel(), durationMs: pulseDuration },
      ],
    },
    {
      id: 'visit',
      title: '10',
      message: 'The Person opens the link and signs in as usual (Microsoft here)',
      actionLabel: '',
      actionEnabled: false,
      phase: 9,
      // Started by the Open link button in PersonNode, not by the control button
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-you-signin', source: 'person', target: 'entity', sourceHandle: 'bottom-left', targetHandle: 'left-top', label: '10. open link + sign in' },
        { type: 'pulse', edge: '10. open link + sign in', durationMs: pulseDuration },
      ],
    },
    {
      id: 'confirm',
      title: '11',
      message: 'The Person Server shows which agent is asking. Confirm it (click Confirm in Person Server).',
      actionLabel: '',
      actionEnabled: false,
      phase: 10,
      // Started by the Confirm button in EntityNode (Person Server); no arrow: it happens on the sign-in's own page
      completeAfterMs: pulseDuration,
    },
    {
      id: 'pass',
      title: '12',
      message: 'The Person Server issues a person token (proof that you approved this agent, for this store)',
      actionLabel: 'Issue',
      phase: 11,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-signin-pass', source: 'entity', target: 'person-agent', sourceHandle: 'right-top', targetHandle: 'bottom-right', label: '12. person token' },
        { type: 'pulse', edge: '12. person token', durationMs: pulseDuration },
      ],
    },
    {
      id: 'done',
      title: '',
      message: 'Now the Agent can show who it works for. Next: the Resource asks to see your profile.',
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
    makeNode("person", "Person"),
    makeNode("person-agent", "Agent"),
    makeNode("agreements", "Agent Provider"),
    makeNode("entity-agent", "Resource"),
    makeNode("control", "Control", { chrome: false }),
    // Last: pairs by order with <EntityNode />, the canvas's last child
    makeNode("entity", "Person Server"),
  ];
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
