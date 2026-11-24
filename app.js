const ISO_CONFIG = {
    github: {
        owner: "ShadowElixir",
        repo: "base-images",
        workflowFile: "build-iso.yml"
    }
};

const runtimeState = {
    de: null,
    gpu: null,
    arch: null,
    channel: null,
    liveData: {
        suiteId: null,
        artifacts: {}
    }
};

document.addEventListener("DOMContentLoaded", () => {
    initializeUIEventListeners();
    fetchLatestArtifacts();
});

function initializeUIEventListeners() {
    document.querySelectorAll(".selector-grid button").forEach(button => {
        button.addEventListener("click", e => {
            const currentButton = e.currentTarget;
            const parentGrid = currentButton.parentElement;
            const step = parentGrid.getAttribute("data-step");
            const value = currentButton.getAttribute("data-value");

            parentGrid.querySelectorAll("button").forEach(btn => btn.classList.remove("active"));
            currentButton.classList.add("active");
            runtimeState[step] = value;

            if (step === "de") {
                document.querySelectorAll('[data-step="gpu"] button, [data-step="arch"] button, [data-step="channel"] button')
                    .forEach(btn => btn.classList.remove("active"));
                runtimeState.gpu = null;
                runtimeState.arch = null;
                runtimeState.channel = null;
            } else if (step === "gpu") {
                document.querySelectorAll('[data-step="arch"] button, [data-step="channel"] button')
                    .forEach(btn => btn.classList.remove("active"));
                runtimeState.arch = null;
                runtimeState.channel = null;
            } else if (step === "arch") {
                document.querySelectorAll('[data-step="channel"] button')
                    .forEach(btn => btn.classList.remove("active"));
                runtimeState.channel = null;
            }

            evaluatePipeline();
        });
    });
}

async function fetchLatestArtifacts() {
    const { owner, repo, workflowFile } = ISO_CONFIG.github;

    const runUrl =
        `https://api.github.com/repos/${owner}/${repo}/actions/workflows/${workflowFile}/runs?status=success&per_page=1`;

    try {
        const runResponse = await fetch(runUrl);
        if (!runResponse.ok) {
            throw new Error(`Workflow API responded with status: ${runResponse.status}`);
        }

        const runData = await runResponse.json();
        if (!runData.workflow_runs || runData.workflow_runs.length === 0) {
            throw new Error("No successful runs discovered in history.");
        }

        const latestRun = runData.workflow_runs[0];
        const runId = latestRun.id.toString();
        runtimeState.liveData.suiteId = latestRun.check_suite_id.toString();

        const artifactsUrl =
            `https://api.github.com/repos/${owner}/${repo}/actions/runs/${runId}/artifacts?per_page=100`;

        const artifactResponse = await fetch(artifactsUrl);
        if (!artifactResponse.ok) {
            throw new Error(`Artifacts API responded with status: ${artifactResponse.status}`);
        }

        const artifactData = await artifactResponse.json();
        if (!artifactData.artifacts || artifactData.artifacts.length === 0) {
            throw new Error("Run contains no artifacts.");
        }

        runtimeState.liveData.artifacts = {};

        artifactData.artifacts.forEach(item => {
            // e.g. bluebuild-kde-nvidia-f45-x86_64-20261121-abc1234.zip (latest)
            //      bluebuild-kde-nvidia-gts-f44-x86_64-20261121-abc1234.zip
            const match = item.name.match(
                /^(bluebuild-[a-z-]+?)-f\d+-(x86_64|arm64)-/
            );
            if (match) {
                const [, prefix, fileArch] = match;
                runtimeState.liveData.artifacts[`${prefix}-${fileArch}`] = {
                    name: item.name,
                    id: item.id.toString()
                };
            }
        });

        console.log("Available variants:", Object.keys(runtimeState.liveData.artifacts));
        evaluatePipeline();
    } catch (error) {
        console.error("Failed to sync remote artifact tree:", error);
    }
}

function setVisible(el, show) {
    if (el) {
        el.classList.toggle("visible", show);
    }
}

function evaluatePipeline() {
    const { de, gpu, arch, channel } = runtimeState;
    const isBase = de === "base";

    setVisible(document.getElementById("step-gpu"), de !== null);
    setVisible(document.getElementById("step-arch"), de !== null && gpu !== null);
    setVisible(document.getElementById("step-channel"), de !== null && gpu !== null && arch !== null);

    const finalDownload = document.getElementById("final-download");
    const downloadBtn = document.querySelector(".dynamic-download-trigger");
    const nvidiaNote = document.getElementById("nvidia-note");
    const baseNote = document.getElementById("base-note");

    if (de === null || gpu === null || arch === null || channel === null) {
        setVisible(finalDownload, false);
        return;
    }

    if (nvidiaNote) {
        nvidiaNote.style.display = gpu !== "" ? "block" : "none";
    }
    if (baseNote) {
        baseNote.style.display = isBase ? "block" : "none";
    }

    // All image families, have standard and NVIDIA variants.
    const variantTarget = `bluebuild-${de}${gpu}${channel}-${arch}`;
    const { owner, repo } = ISO_CONFIG.github;

    const disable = opacity => {
        if (downloadBtn) {
            downloadBtn.removeAttribute("href");
            downloadBtn.style.pointerEvents = "none";
            downloadBtn.style.opacity = opacity;
        }
    };

    if (!runtimeState.liveData.suiteId || Object.keys(runtimeState.liveData.artifacts).length === 0) {
        disable("0.4");
        setVisible(finalDownload, true);
        return;
    }

    const matched = runtimeState.liveData.artifacts[variantTarget];

    if (matched) {
        if (downloadBtn) {
            downloadBtn.href =
                `https://nightly.link/${owner}/${repo}` +
                `/suites/${runtimeState.liveData.suiteId}` +
                `/artifacts/${matched.id}`;
            downloadBtn.style.pointerEvents = "auto";
            downloadBtn.style.opacity = "1";
        }
    } else {
        disable("0.15");
        console.warn(`No artifact found for variant: ${variantTarget}`);
    }

    setVisible(finalDownload, true);
}
