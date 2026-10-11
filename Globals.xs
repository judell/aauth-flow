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

  // A sub-step of a frame plays as soon as the previous sub-step finishes,
  // so one frame can show several arrows in order
  if (step.autoRun) {
    nextStep();
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
    outcome = '';
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

  applyStep(nextIndex(stepIndex, trigger, outcome));
}

// The one branching rule, used by playback and by URL jumps.
// Act 1 is interactive; act 2 (scheduled) diverges at frame 5.
function nextIndex(i, kind, oc) {
  const steps = getProcessFlowSteps();
  const id = steps[i].id;
  if (id === 'needok') return findStepIndex(kind === 'scheduled' ? 'choose' : 'approvehere');
  if (id === 'choose') {
    if (oc === 'mission') return findStepIndex('mission');
    if (oc === 'ask') return findStepIndex('approvehere');
    return findStepIndex('unreachable');
  }
  if (id === 'mission') return findStepIndex('vouches');
  if (id === 'paid') return findStepIndex('end');
  if (id === 'unreachable') return findStepIndex('end2');
  return Math.min(i + 1, steps.length - 1);
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

// Draws frame 1's arrow (Person -> Agent) for the given act; returns its label
function addTriggerEdge(kind) {
  const scheduled = kind === 'scheduled';
  const label = scheduled ? '1. 3 a.m.: weekly reorder fires' : '1. buy';
  window.__reactFlowCanvasApi.addEdge('e-you-agent', 'person', 'person-agent',
    scheduled ? 'right-bottom' : 'right-top',
    scheduled ? 'left-bottom' : 'left-top', label);
  return label;
}

// Node-driven start: the Buy button (act 1) or the calendar icon (act 2) in PersonNode
function startBuy(kind) {
  if (stepIndex !== 0 || running) return;
  trigger = kind;
  outcome = '';
  buttonEnabled = false;
  running = true;
  const label = addTriggerEdge(kind);
  window.__reactFlowCanvasApi.pulseEdge(label, pulseDuration);
}

// Node-driven: act 2's choice in PersonNode (what can the Person Server do at 3 a.m.?)
function chooseOutcome(o) {
  if (running) return;
  outcome = o;
  nextStep();
}

// --- Step URL: ?step=N[&path=scheduled][&outcome=mission|ask|neither] ---

// Query string for the current step (written to the URL by ReactFlowPage).
// A string, because the vendored XMLUI 0.12.15 navigate() ignores the
// { queryParams, replace } options that 0.14 documents.
function stepQueryString() {
  const steps = getProcessFlowSteps();
  const step = steps[stepIndex];
  return urlStepString(step.title || 'end', trigger, outcome);
}

// The same string for values read from the URL, for comparison
function urlStepString(step, path, oc) {
  return 'step=' + step + (path === 'scheduled' ? '&path=scheduled' : '') + (oc ? '&outcome=' + oc : '');
}

// Arrive at frame n (or 'end') with everything before it already done.
// Walks the path a viewer would take (following nextIndex), drawing each
// visited step's arrows without pulsing; phase gates reveal node contents.
function jumpToStep(n, path, oc) {
  const kind = path === 'scheduled' ? 'scheduled' : 'interactive';
  const o = oc || '';
  const steps = getProcessFlowSteps();
  const visited = [];
  let i = 0;
  let target = -1;
  for (let guard = 0; guard < 80; guard++) {
    const st = steps[i];
    const hit = n === 'end' ? st.restartOnAction : st.title === String(n);
    if (hit) { target = i; break; }
    if (st.restartOnAction) break;
    visited.push(i);
    i = nextIndex(i, kind, o);
  }
  if (target < 0) return;
  const api = window.__reactFlowCanvasApi;
  api.clearPulse();
  const ids = sceneEdgeIds();
  for (let k = 0; k < ids.length; k++) {
    api.removeEdge(ids[k]);
  }
  running = false;
  pulse = { active: false, edges: [], step: -1, currentEdge: '' };
  if (target === 0) {
    // step=1: back to the start, nothing drawn yet
    trigger = '';
    outcome = '';
    applyStep(0);
    return;
  }
  trigger = kind;
  outcome = o;
  for (let v = 0; v < visited.length; v++) {
    if (visited[v] === 0) {
      addTriggerEdge(kind);
      continue;
    }
    const effects = steps[visited[v]].run || [];
    for (let j = 0; j < effects.length; j++) {
      const e = effects[j];
      if (e.type === 'addEdge') {
        const label = e.id === 'e-agent-you' ? approveLabelFor(kind) : e.label;
        api.addEdge(e.id, e.source, e.target, e.sourceHandle, e.targetHandle, label, e.noArrow, e.data);
      }
    }
  }
  applyStep(target);
}

// --- Step declarations ---

// Edges this sequence adds; restart removes them
function sceneEdgeIds() {
  return ['e-you-agent', 'e-agent-home', 'e-home-agent', 'e-agent-svc', 'e-svc-home', 'e-svc-agent',
    'e-agent-signin', 'e-signin-agent', 'e-agent-you', 'e-you-signin',
    'e-signin-vouch', 'e-agent-retry', 'e-svc-needperm', 'e-agent-permask', 'e-signin-grant', 'e-agent-pay',
    'e-signin-unreach'];
}

function approveLabel() {
  return approveLabelFor(trigger);
}

function approveLabelFor(kind) {
  return kind === 'scheduled' ? '5. notification on your phone: approve?' : '5. approve here';
}

// Arrows that share a pair of handles get staggered label positions (percent along the edge)
function lp(pct) {
  return { labelPosition: pct };
}

// Phases equal step indexes (vouch's runningPhase 6.5 brings in the Person Server).
// Node gates in the components use these numbers; keep them in sync.
function getProcessFlowSteps() {
  return [
    // --- Act 1: when you're there (interactive). Act 2 (scheduled) shares frames 1-5 ---
    {
      id: 'trigger', // 0
      title: '1',
      message: 'The Person (you) buys something (click Buy). Act 2: a weekly reorder fires at 3 a.m. while you sleep (click the calendar).',
      actionLabel: '',
      actionEnabled: false,
      phase: 0,
      completeAfterMs: pulseDuration,
      // Started by startBuy() from PersonNode, not by the control button
    },
    {
      id: 'ask', // 1
      title: '2',
      message: "The Agent (your assistant) gets its own signed ID, an agent token, from its Agent Provider (the agent's home; here self-hosted, on Jon's own site)",
      actionLabel: 'Get ID',
      phase: 1,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-agent-home', source: 'person-agent', target: 'agreements', sourceHandle: 'top-left', targetHandle: 'bottom-left', label: '2. asks for its ID' },
        { type: 'pulse', edge: '2. asks for its ID', durationMs: pulseDuration },
      ],
    },
    {
      id: 'issue', // 2
      title: '2',
      message: "The Agent (your assistant) gets its own signed ID, an agent token, from its Agent Provider (the agent's home; here self-hosted, on Jon's own site)",
      actionLabel: '',
      phase: 2,
      autoRun: true,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-home-agent', source: 'agreements', target: 'person-agent', sourceHandle: 'bottom-right', targetHandle: 'top-right', label: '2. issues its ID' },
        { type: 'pulse', edge: '2. issues its ID', durationMs: pulseDuration },
      ],
    },
    {
      id: 'request', // 3
      title: '3',
      message: "The Agent sends the buy request with its agent token to the Resource (the store), which checks it against the Agent Provider's published key. Now it knows which agent this is, but not who it's buying for.",
      actionLabel: 'Send',
      phase: 3,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-agent-svc', source: 'person-agent', target: 'entity-agent', sourceHandle: 'right-top', targetHandle: 'left-top', label: '3. buy request + agent token', data: lp(25) },
        { type: 'pulse', edge: '3. buy request + agent token', durationMs: pulseDuration },
      ],
    },
    {
      id: 'check', // 4
      title: '3',
      message: "The Agent sends the buy request with its agent token to the Resource (the store), which checks it against the Agent Provider's published key. Now it knows which agent this is, but not who it's buying for.",
      actionLabel: '',
      phase: 4,
      autoRun: true,
      completeAfterRoundTrip: true,
      run: [
        { type: 'addEdge', id: 'e-svc-home', source: 'entity-agent', target: 'agreements', sourceHandle: 'top-left', targetHandle: 'right-bottom', label: "3. checks the agent's ID" },
        { type: 'pulseRoundTrip', edge: "3. checks the agent's ID", durationMs: pulseDuration },
      ],
    },
    {
      id: 'answer', // 5
      title: '3',
      message: "The Agent sends the buy request with its agent token to the Resource (the store), which checks it against the Agent Provider's published key. Now it knows which agent this is, but not who it's buying for.",
      actionLabel: '',
      phase: 5,
      autoRun: true,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-svc-agent', source: 'entity-agent', target: 'person-agent', sourceHandle: 'left-bottom', targetHandle: 'right-bottom', label: '3. who are you buying for?', data: lp(30) },
        { type: 'pulse', edge: '3. who are you buying for?', durationMs: pulseDuration },
      ],
    },
    {
      id: 'vouch', // 6
      title: '4',
      message: 'The agent token names the Agent\'s Person Server (your sign-in), so the Agent asks it to vouch for its Person',
      actionLabel: 'Ask',
      phase: 6,
      runningPhase: 6.5,
      completeAfterMs: pulseDuration,
      // The Person Server's "not involved yet" line clears at phase >= 6.5 (EntityNode)
      run: [
        { type: 'addEdge', id: 'e-agent-signin', source: 'person-agent', target: 'entity', sourceHandle: 'bottom-left', targetHandle: 'top-left', label: '4. vouch for my Person?', data: lp(35) },
        { type: 'pulse', edge: '4. vouch for my Person?', durationMs: pulseDuration },
      ],
    },
    {
      id: 'needok', // 7
      title: '5',
      message: trigger === 'scheduled'
        ? "The Person Server needs your OK, but it's 3 a.m. and nobody is at the screen"
        : 'The Person Server needs your OK, so the Agent shows you where to approve',
      actionLabel: 'Continue',
      phase: 7,
      completeAfterMs: pulseDuration,
      // Branches: interactive -> approvehere; scheduled -> choose (nextIndex)
      run: [
        { type: 'addEdge', id: 'e-signin-agent', source: 'entity', target: 'person-agent', sourceHandle: 'right-top', targetHandle: 'bottom-right', label: '5. needs your OK', data: lp(30) },
        { type: 'pulse', edge: '5. needs your OK', durationMs: pulseDuration },
      ],
    },
    {
      id: 'approvehere', // 8
      title: '5',
      message: trigger === 'scheduled'
        ? 'The Person Server reaches you another way: a notification on your phone'
        : 'The Person Server needs your OK, so the Agent shows you where to approve',
      actionLabel: '',
      phase: 8,
      autoRun: true,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-agent-you', source: 'person-agent', target: 'person', sourceHandle: 'left-bottom', targetHandle: 'bottom-right', label: approveLabel() },
        { type: 'pulse', edge: approveLabel(), durationMs: pulseDuration },
      ],
    },
    {
      id: 'visit', // 9
      title: '6',
      message: 'You open the link and sign in as usual, Microsoft here (click Open link in Person)',
      actionLabel: '',
      actionEnabled: false,
      phase: 9,
      // Started by the Open link button in PersonNode
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-you-signin', source: 'person', target: 'entity', sourceHandle: 'bottom-left', targetHandle: 'left-top', label: '6. open link + sign in' },
        { type: 'pulse', edge: '6. open link + sign in', durationMs: pulseDuration },
      ],
    },
    {
      id: 'confirm', // 10
      title: '6',
      message: 'You approve this agent, at this store, and nowhere else (click Confirm in Person Server)',
      actionLabel: '',
      actionEnabled: false,
      phase: 10,
      // Started by the Confirm button in EntityNode; no arrow: it happens on the sign-in's own page
      completeAfterMs: pulseDuration,
    },
    {
      id: 'vouches', // 11
      title: '7',
      message: 'The Person Server vouches for you with a private ID only this store sees (person token): no name, no password. The Agent retries, and the Resource now knows who it\'s buying for.',
      actionLabel: 'Vouch',
      phase: 11,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-signin-vouch', source: 'entity', target: 'person-agent', sourceHandle: 'right-bottom', targetHandle: 'bottom-right', label: '7. vouches for you (private ID)', data: lp(65) },
        { type: 'pulse', edge: '7. vouches for you (private ID)', durationMs: pulseDuration },
      ],
    },
    {
      id: 'retry', // 12
      title: '7',
      message: 'The Person Server vouches for you with a private ID only this store sees (person token): no name, no password. The Agent retries, and the Resource now knows who it\'s buying for.',
      actionLabel: '',
      phase: 12,
      autoRun: true,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-agent-retry', source: 'person-agent', target: 'entity-agent', sourceHandle: 'right-top', targetHandle: 'left-top', label: '7. retry, with the voucher', data: lp(55) },
        { type: 'pulse', edge: '7. retry, with the voucher', durationMs: pulseDuration },
      ],
    },
    {
      id: 'needperm', // 13
      title: '7',
      message: 'The Person Server vouches for you with a private ID only this store sees (person token): no name, no password. The Agent retries, and the Resource now knows who it\'s buying for.',
      actionLabel: '',
      phase: 13,
      autoRun: true,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-svc-needperm', source: 'entity-agent', target: 'person-agent', sourceHandle: 'left-bottom', targetHandle: 'right-bottom', label: '7. I know who; now, permission?', data: lp(70) },
        { type: 'pulse', edge: '7. I know who; now, permission?', durationMs: pulseDuration },
      ],
    },
    {
      id: 'permask', // 14
      title: '8',
      message: 'The Agent asks the Person Server for permission for this purchase. It grants it (auth token), and the purchase goes through.',
      actionLabel: 'Get permission',
      phase: 14,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-agent-permask', source: 'person-agent', target: 'entity', sourceHandle: 'bottom-left', targetHandle: 'top-right', label: '8. permission for this purchase?', data: lp(70) },
        { type: 'pulse', edge: '8. permission for this purchase?', durationMs: pulseDuration },
      ],
    },
    {
      id: 'grant', // 15
      title: '8',
      message: 'The Agent asks the Person Server for permission for this purchase. It grants it (auth token), and the purchase goes through.',
      actionLabel: '',
      phase: 15,
      autoRun: true,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-signin-grant', source: 'entity', target: 'person-agent', sourceHandle: 'bottom-right', targetHandle: 'bottom-right', label: '8. granted (auth token)', data: lp(80) },
        { type: 'pulse', edge: '8. granted (auth token)', durationMs: pulseDuration },
      ],
    },
    {
      id: 'paid', // 16
      title: '8',
      message: 'The Agent asks the Person Server for permission for this purchase. It grants it (auth token), and the purchase goes through.',
      actionLabel: '',
      phase: 16,
      autoRun: true,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-agent-pay', source: 'person-agent', target: 'entity-agent', sourceHandle: 'right-top', targetHandle: 'left-top', label: '8. buy, with permission: done', data: lp(85) },
        { type: 'pulse', edge: '8. buy, with permission: done', durationMs: pulseDuration },
      ],
    },
    {
      id: 'end', // 17
      title: '',
      message: trigger === 'scheduled'
        ? 'Bought at 3 a.m. with no prompt, because you approved the weekly reorder at this store last week. Today an agent acting while you sleep would need your password or a shared key that could leak; here it carries its own identity, and you approve it store by store.'
        : 'Why it matters: today, an agent buying something for you has your password or a shared key that could leak. Here, it carries its own identity, you approve it store by store, and the store never needs your password. Next: act 2, when you\'re not there.',
      actionLabel: 'Start over',
      phase: 17,
      restartOnAction: true,
    },
    // --- Act 2 divergence: 3 a.m., nobody at the screen (per spec; not observed in our run) ---
    {
      id: 'choose', // 18
      title: '5',
      message: 'Nobody is at the screen. What can the Person Server do? (choose in Person)',
      actionLabel: '',
      actionEnabled: false,
      phase: 18,
      // Started by chooseOutcome() from PersonNode
      completeAfterMs: pulseDuration,
    },
    {
      id: 'mission', // 19
      title: '6',
      message: 'You approved the weekly reorder at this store last week (a mission), so the Person Server needs no prompt',
      actionLabel: 'Continue',
      phase: 19,
      completeAfterMs: pulseDuration,
    },
    {
      id: 'unreachable', // 20
      title: '6',
      message: "The Person Server can't reach you, so it tells the Agent so (user_unreachable)",
      actionLabel: 'Continue',
      phase: 20,
      completeAfterMs: pulseDuration,
      run: [
        { type: 'addEdge', id: 'e-signin-unreach', source: 'entity', target: 'person-agent', sourceHandle: 'right-bottom', targetHandle: 'bottom-right', label: "6. can't reach the Person" },
        { type: 'pulse', edge: "6. can't reach the Person", durationMs: pulseDuration },
      ],
    },
    {
      id: 'end2', // 21
      title: '',
      message: 'Nothing is bought without you: the reorder waits. The Person Server is what lets an agent act while you\'re away, without holding your keys.',
      actionLabel: 'Start over',
      phase: 21,
      restartOnAction: true,
    },
  ];
}

// --- Node & edge builders ---

// Saving the layout writes only the nodes on the canvas, so a node hidden at save
// time can be missing from layout.json.
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
