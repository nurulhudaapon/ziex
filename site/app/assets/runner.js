(function () {
    const SLOW_PX_PER_SEC = 55;
    const FLEE_PX_PER_SEC = 420;
    const BOB_SLOW = "0.42s";
    const BOB_FAST = "0.14s";
    const RUNNER_WIDTH = 72;

    const PERSONAS = [
        { idle: "catch me!",     clicked: "oops!",     sound: "aa",     fx: "fx-shake" },
        { idle: "too slow!",     clicked: "ouch!",     sound: "boing",  fx: "fx-squish" },
        { idle: "betcha can't",  clicked: "rude!",     sound: "honk",   fx: "fx-spin" },
        { idle: "zoom zoom",     clicked: "yikes!",    sound: "laser",  fx: "fx-flash" },
        { idle: "hi there 👋",   clicked: "byeee",     sound: "bubble", fx: "fx-squish" },
        { idle: "not it!",       clicked: "tagged!",   sound: "bonk",   fx: "fx-shake" },
        { idle: "I'm fast",      clicked: "hey!",      sound: "squeak", fx: "fx-spin" },
        { idle: "skrrt",         clicked: "wahhh",     sound: "slide",  fx: "fx-flash" },
    ];
    let personaIdx = 0;
    function nextPersona() {
        const p = PERSONAS[personaIdx % PERSONAS.length];
        personaIdx++;
        return p;
    }

    function randRange(a, b) { return a + Math.random() * (b - a); }

    function createRunnerMarkup(idleText) {
        const host = document.createElement("div");
        host.className = "footer-runner section-runner";
        host.innerHTML =
            '<div class="footer-runner-wrap">' +
                '<div class="footer-runner-bubble"></div>' +
                '<img class="footer-runner-mascot" src="/assets/mascot.svg" alt="Running Ziguana" />' +
            '</div>';
        host.querySelector(".footer-runner-bubble").textContent = idleText;
        return host;
    }

    function attachRunner(wrap, persona) {
        persona = persona || PERSONAS[0];
        const mascot = wrap.querySelector(".footer-runner-mascot");
        const bubble = wrap.querySelector(".footer-runner-bubble");
        if (!mascot) return;

        let x = -RUNNER_WIDTH;
        let dir = 1;
        let paused = false;
        let fleeUntil = 0;
        let nextPauseAt = performance.now() + randRange(1800, 3200);
        let resumeAt = 0;
        let last = performance.now();
        if (bubble) bubble.textContent = persona.idle;
        const defaultBubbleText = persona.idle;
        let bubbleResetAt = 0;

        function setBob(v) { mascot.style.setProperty("--runner-bob", v); }
        setBob(BOB_SLOW);

        function frame(now) {
            const dt = Math.min(50, now - last) / 1000;
            last = now;

            if (paused) {
                if (now >= resumeAt) {
                    paused = false;
                    wrap.classList.remove("is-paused");
                    nextPauseAt = now + randRange(2000, 3500);
                }
            } else {
                const fleeing = now < fleeUntil;
                const speed = fleeing ? FLEE_PX_PER_SEC : SLOW_PX_PER_SEC;
                setBob(fleeing ? BOB_FAST : BOB_SLOW);

                x += dir * speed * dt;
                const parentW = wrap.parentElement ? wrap.parentElement.clientWidth : 0;
                const maxX = Math.max(0, parentW - RUNNER_WIDTH);
                if (dir === 1 && x > maxX) {
                    x = maxX;
                    dir = -1;
                    wrap.classList.add("is-flipped");
                } else if (dir === -1 && x < -RUNNER_WIDTH) {
                    x = -RUNNER_WIDTH;
                    dir = 1;
                    wrap.classList.remove("is-flipped");
                }
                wrap.style.transform = "translateX(" + x.toFixed(1) + "px)";

                if (!fleeing && now >= nextPauseAt) {
                    paused = true;
                    wrap.classList.add("is-paused");
                    resumeAt = now + randRange(900, 1500);
                }
            }

            if (bubble && bubbleResetAt && now >= bubbleResetAt) {
                bubble.textContent = defaultBubbleText;
                bubbleResetAt = 0;
            }

            requestAnimationFrame(frame);
        }
        requestAnimationFrame(function (t) { last = t; frame(t); });

        mascot.addEventListener("click", function () {
            const now = performance.now();
            if (bubble) {
                bubble.textContent = persona.clicked;
                bubbleResetAt = now + 1400;
            }
            paused = true;
            wrap.classList.add("is-paused");
            resumeAt = now + 350;
            fleeUntil = now + 350 + 2200;
            mascot.classList.remove("fx-spin", "fx-shake", "fx-squish", "fx-flash");
            void mascot.offsetWidth;
            mascot.classList.add(persona.fx || "fx-shake");
            playSound(persona.sound);
        });
    }

    let audioCtx;
    function getCtx() {
        audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
        return audioCtx;
    }

    function playSound(kind) {
        const fn = SOUNDS[kind] || SOUNDS.aa;
        try { fn(); } catch (e) {}
    }

    const SOUNDS = {
        aa: aaSound,
        boing: boingSound,
        honk: honkSound,
        laser: laserSound,
        bubble: bubbleSound,
        bonk: bonkSound,
        squeak: squeakSound,
        slide: slideSound,
    };

    function aaSound() {
        {
            const ctx = getCtx();
            const now = ctx.currentTime;
            const dur = 0.5;

            const osc = ctx.createOscillator();
            osc.type = "sawtooth";
            osc.frequency.setValueAtTime(420, now);
            osc.frequency.linearRampToValueAtTime(360, now + dur);

            const vibrato = ctx.createOscillator();
            vibrato.frequency.value = 5.5;
            const vibGain = ctx.createGain();
            vibGain.gain.value = 12;
            vibrato.connect(vibGain).connect(osc.frequency);

            const formant = ctx.createBiquadFilter();
            formant.type = "bandpass";
            formant.frequency.value = 900;
            formant.Q.value = 4;

            const gain = ctx.createGain();
            gain.gain.setValueAtTime(0, now);
            gain.gain.linearRampToValueAtTime(0.35, now + 0.04);
            gain.gain.setValueAtTime(0.35, now + dur - 0.08);
            gain.gain.exponentialRampToValueAtTime(0.0001, now + dur);

            osc.connect(formant).connect(gain).connect(ctx.destination);
            osc.start(now); vibrato.start(now);
            osc.stop(now + dur); vibrato.stop(now + dur);
        }
    }

    function boingSound() {
        const ctx = getCtx();
        const now = ctx.currentTime;
        const dur = 0.45;
        const osc = ctx.createOscillator();
        osc.type = "sine";
        osc.frequency.setValueAtTime(180, now);
        osc.frequency.exponentialRampToValueAtTime(720, now + 0.08);
        osc.frequency.exponentialRampToValueAtTime(200, now + dur);
        const g = ctx.createGain();
        g.gain.setValueAtTime(0.0001, now);
        g.gain.exponentialRampToValueAtTime(0.4, now + 0.02);
        g.gain.exponentialRampToValueAtTime(0.0001, now + dur);
        osc.connect(g).connect(ctx.destination);
        osc.start(now); osc.stop(now + dur);
    }

    function honkSound() {
        const ctx = getCtx();
        const now = ctx.currentTime;
        const dur = 0.3;
        const osc = ctx.createOscillator();
        osc.type = "square";
        osc.frequency.value = 220;
        const lp = ctx.createBiquadFilter();
        lp.type = "lowpass"; lp.frequency.value = 1200;
        const g = ctx.createGain();
        g.gain.setValueAtTime(0, now);
        g.gain.linearRampToValueAtTime(0.3, now + 0.02);
        g.gain.setValueAtTime(0.3, now + dur - 0.05);
        g.gain.exponentialRampToValueAtTime(0.0001, now + dur);
        osc.connect(lp).connect(g).connect(ctx.destination);
        osc.start(now); osc.stop(now + dur);
    }

    function laserSound() {
        const ctx = getCtx();
        const now = ctx.currentTime;
        const dur = 0.35;
        const osc = ctx.createOscillator();
        osc.type = "sawtooth";
        osc.frequency.setValueAtTime(1800, now);
        osc.frequency.exponentialRampToValueAtTime(120, now + dur);
        const g = ctx.createGain();
        g.gain.setValueAtTime(0.3, now);
        g.gain.exponentialRampToValueAtTime(0.0001, now + dur);
        osc.connect(g).connect(ctx.destination);
        osc.start(now); osc.stop(now + dur);
    }

    function bubbleSound() {
        const ctx = getCtx();
        const now = ctx.currentTime;
        const dur = 0.25;
        const osc = ctx.createOscillator();
        osc.type = "sine";
        osc.frequency.setValueAtTime(400, now);
        osc.frequency.exponentialRampToValueAtTime(1600, now + dur);
        const g = ctx.createGain();
        g.gain.setValueAtTime(0.0001, now);
        g.gain.exponentialRampToValueAtTime(0.3, now + 0.05);
        g.gain.exponentialRampToValueAtTime(0.0001, now + dur);
        osc.connect(g).connect(ctx.destination);
        osc.start(now); osc.stop(now + dur);
    }

    function bonkSound() {
        const ctx = getCtx();
        const now = ctx.currentTime;
        const dur = 0.2;
        const bufSize = Math.floor(ctx.sampleRate * dur);
        const buf = ctx.createBuffer(1, bufSize, ctx.sampleRate);
        const data = buf.getChannelData(0);
        for (let i = 0; i < bufSize; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / bufSize);
        const src = ctx.createBufferSource(); src.buffer = buf;
        const bp = ctx.createBiquadFilter();
        bp.type = "bandpass"; bp.frequency.value = 220; bp.Q.value = 5;
        const g = ctx.createGain();
        g.gain.setValueAtTime(0.6, now);
        g.gain.exponentialRampToValueAtTime(0.0001, now + dur);
        src.connect(bp).connect(g).connect(ctx.destination);
        src.start(now); src.stop(now + dur);
    }

    function squeakSound() {
        const ctx = getCtx();
        const now = ctx.currentTime;
        const dur = 0.18;
        const osc = ctx.createOscillator();
        osc.type = "triangle";
        osc.frequency.setValueAtTime(1200, now);
        osc.frequency.exponentialRampToValueAtTime(2400, now + dur);
        const g = ctx.createGain();
        g.gain.setValueAtTime(0.0001, now);
        g.gain.exponentialRampToValueAtTime(0.25, now + 0.02);
        g.gain.exponentialRampToValueAtTime(0.0001, now + dur);
        osc.connect(g).connect(ctx.destination);
        osc.start(now); osc.stop(now + dur);
    }

    function slideSound() {
        const ctx = getCtx();
        const now = ctx.currentTime;
        const dur = 0.5;
        const bufSize = Math.floor(ctx.sampleRate * dur);
        const buf = ctx.createBuffer(1, bufSize, ctx.sampleRate);
        const data = buf.getChannelData(0);
        for (let i = 0; i < bufSize; i++) data[i] = (Math.random() * 2 - 1);
        const src = ctx.createBufferSource(); src.buffer = buf;
        const bp = ctx.createBiquadFilter();
        bp.type = "bandpass"; bp.Q.value = 8;
        bp.frequency.setValueAtTime(500, now);
        bp.frequency.exponentialRampToValueAtTime(2500, now + dur);
        const g = ctx.createGain();
        g.gain.setValueAtTime(0.3, now);
        g.gain.exponentialRampToValueAtTime(0.0001, now + dur);
        src.connect(bp).connect(g).connect(ctx.destination);
        src.start(now); src.stop(now + dur);
    }

    function init() {
        document.querySelectorAll(".footer-runner .footer-runner-wrap").forEach(function (w) {
            attachRunner(w, nextPersona());
        });

        const RUNNER_SECTIONS = ".performance, .deployment, .feature-examples, .benchmarks";
        document.querySelectorAll(RUNNER_SECTIONS).forEach(function (section) {
            if (section.querySelector(":scope > .section-runner")) return;
            if (getComputedStyle(section).position === "static") {
                section.style.position = "relative";
            }
            const persona = nextPersona();
            const host = createRunnerMarkup(persona.idle);
            section.prepend(host);
            attachRunner(host.querySelector(".footer-runner-wrap"), persona);
        });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }
})();
