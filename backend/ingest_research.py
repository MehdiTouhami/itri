"""
ingest_research.py — Embed peer-reviewed sleep and training papers into Qdrant Cloud.
Run: python3 ingest_research.py   (recreates the collection, so re-run after adding papers)

18 sleep science papers plus 7 training and recovery papers added for the merged Itri app.
Sources: Nature Reviews Neuroscience, JAMA, Sleep, PNAS, European Heart Journal, etc.

Vectors persist in Qdrant Cloud (free tier), so this only needs to run the
first time — main.py's lifespan checks whether the collection is already
seeded before calling this on every boot.
"""

import os
import time
from dotenv import load_dotenv
from langchain_google_genai import GoogleGenerativeAIEmbeddings
from langchain_qdrant import QdrantVectorStore
from langchain_core.documents import Document
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams

load_dotenv()

QDRANT_URL = os.environ["QDRANT_URL"]
QDRANT_API_KEY = os.environ["QDRANT_API_KEY"]
COLLECTION_NAME = "research_papers"

# gemini-embedding-001's default output dimensionality.
EMBEDDING_SIZE = 3072

RESEARCH_PAPERS = [
    {
        "topic": "REM Sleep and Memory Consolidation",
        "citation": "Plihal & Born (1999). Effects of Early and Late Nocturnal Sleep on Priming and Spatial Memory. Psychophysiology. ~559 citations.",
        "content": (
            "This experiment compared early-night sleep (slow-wave-sleep-rich) with late-night sleep "
            "(REM-rich) and showed different memory tasks benefit from different parts of the night. "
            "Spatial and declarative memory favoured early sleep, while other memory types showed "
            "different patterns — establishing that sleep stages are not interchangeable for cognition. "
            "It is one of the clearest early stage-dissociation studies in human sleep-memory research."
        ),
    },
    {
        "topic": "REM Sleep, Memory Consolidation, and Sleep Architecture",
        "citation": "Diekelmann & Born (2010). The Memory Function of Sleep. Nature Reviews Neuroscience. 3,568 citations.",
        "content": (
            "This major review argues that sleep actively consolidates declarative, procedural, and "
            "emotional memories rather than simply protecting them from interference. It integrates "
            "evidence for hippocampo-neocortical reactivation during non-REM sleep while showing that "
            "REM sleep supports integration, emotional processing, and qualitative memory changes. "
            "It remains the central synthesis paper unifying disparate sleep-memory findings into a "
            "mechanistic framework still cited and debated today."
        ),
    },
    {
        "topic": "Deep Sleep, Growth Hormone, and Physical Recovery",
        "citation": "Van Cauter, Leproult & Plat (2000). Age-Related Changes in Slow Wave Sleep and REM Sleep and Relationship With Growth Hormone and Cortisol Levels in Healthy Men. JAMA.",
        "content": (
            "This foundational paper links large reductions in slow-wave (deep) sleep to reduced "
            "growth-hormone secretion, while REM decline tracks with higher evening cortisol. "
            "It provides one of the strongest demonstrations that sleep architecture and "
            "anabolic/catabolic endocrine balance move together. It is the key anchor paper for why "
            "slow-wave sleep is treated as the most physically restorative portion of sleep, "
            "despite not measuring tissue repair directly."
        ),
    },
    {
        "topic": "HRV as a Biomarker — Standards of Measurement",
        "citation": "Task Force of the European Society of Cardiology (1996). Heart Rate Variability: Standards of Measurement, Physiological Interpretation, and Clinical Use. European Heart Journal. 15,200+ citations.",
        "content": (
            "This is the foundational standards document for heart rate variability (HRV) — the paper "
            "that made all later 'HRV as sleep biomarker' research technically legible across studies. "
            "It formalised core time-domain and frequency-domain measures and gave the field a common "
            "language for interpreting beat-to-beat variability as an autonomic marker. Without it, "
            "the literature on nocturnal HRV, sleep-stage differences, and wearable recovery metrics "
            "would be far less coherent. Higher overnight HRV indicates greater parasympathetic "
            "activity and better cardiovascular recovery."
        ),
    },
    {
        "topic": "HRV During Sleep — Autonomic Balance Tracking",
        "citation": "Otzenberger et al. (1998). Dynamic heart rate variability: a tool for exploring sympathovagal balance continuously during sleep in men. American Journal of Physiology.",
        "content": (
            "This paper is one of the classic demonstrations that HRV can track changing autonomic "
            "balance across the night rather than only in waking laboratory conditions. It helped "
            "establish that nocturnal cardiac variability contains physiologically meaningful "
            "information about sleep-stage and sleep-cycle dynamics. Modern wearable 'sleep recovery' "
            "scoring — including Garmin's Body Battery — depends on principles traced back to papers "
            "like this one."
        ),
    },
    {
        "topic": "Resting Heart Rate and Autonomic Activity During Sleep Stages",
        "citation": "Trinder et al. (2001). Autonomic Activity During Human Sleep as a Function of Time and Sleep Stage. Journal of Sleep Research.",
        "content": (
            "This study examined autonomic changes across both sleep stage and time of night, showing "
            "that nocturnal heart rate and HRV are shaped by more than stage labels alone. It clarified "
            "that cardiovascular physiology during sleep is dynamic and organised over the course of "
            "the night, not static within a single 'sleep' state. An elevated resting HR during sleep "
            "— particularly above your personal baseline — indicates physiological stress, illness, "
            "intense exercise recovery, or alcohol effects."
        ),
    },
    {
        "topic": "Sleep Duration and Cognitive Performance — Chronic Restriction",
        "citation": "Van Dongen et al. (2003). The Cumulative Cost of Additional Wakefulness: Dose-Response Effects on Neurobehavioral Functions and Sleep Physiology From Chronic Sleep Restriction and Total Sleep Deprivation. Sleep. 3,100+ citations.",
        "content": (
            "The landmark dose-response paper showing that sleeping 4–6 hours per night for 14 days "
            "produces large cumulative neurobehavioral deficits. Crucially, participants' subjective "
            "sleepiness rose much less dramatically than their actual performance impairment — people "
            "chronically underestimate the cognitive cost of restricted sleep. This is one of the "
            "clearest empirical bases for the claim that 'moderate' sleep loss is not cognitively "
            "benign. Optimal sleep duration for most adults is 7–9 hours per night."
        ),
    },
    {
        "topic": "Sleep Debt and Recovery — Performance Restoration",
        "citation": "Belenky et al. (2003). Patterns of Performance Degradation and Restoration during Sleep Restriction and Subsequent Recovery: A Sleep Dose-Response Study. Journal of Sleep Research.",
        "content": (
            "This study examined multiple levels of time in bed then followed performance into "
            "recovery sleep, showing both graded deterioration with restricted sleep and a "
            "non-instantaneous return toward baseline when sleep opportunity was restored. "
            "Sleep debt has real recovery dynamics — a single recovery night does not fully "
            "reverse accumulated deficits. It helped formalise 'sleep dose-response' thinking "
            "and showed that full cognitive restoration may require several nights of adequate sleep."
        ),
    },
    {
        "topic": "Caffeine and Deep Sleep Architecture",
        "citation": "Landolt et al. (1995). Caffeine Reduces Low-Frequency Delta Activity in the Human Sleep EEG. Neuropsychopharmacology.",
        "content": (
            "This experiment showed that even a relatively low bedtime caffeine dose suppresses "
            "low-frequency delta power and reduces stage 4 (deep) sleep, directly linking caffeine "
            "to the electrophysiology of sleep depth. It goes beyond 'feeling less sleepy' and "
            "demonstrates a measurable change in slow-wave sleep itself. It is one of the canonical "
            "mechanistic papers on why caffeine affects not only sleep onset but also sleep quality "
            "and homeostatic intensity. Caffeine's half-life is 5–7 hours."
        ),
    },
    {
        "topic": "Caffeine Timing and Sleep — 6-Hour Effect",
        "citation": "Drake et al. (2013). Caffeine Effects on Sleep Taken 0, 3, or 6 Hours before Going to Bed. Journal of Clinical Sleep Medicine.",
        "content": (
            "This study tested the same caffeine dose at different intervals before bedtime in "
            "real-world conditions, finding significant sleep disruption even when caffeine was "
            "taken 6 hours before bed. It translates lab-style caffeine findings into a "
            "behaviourally usable timing rule. The practical implication: cutting off caffeine "
            "by early afternoon is evidence-based advice, not overcaution, for most people — "
            "especially slow caffeine metabolisers."
        ),
    },
    {
        "topic": "Exercise and Sleep Quality — Meta-Analysis",
        "citation": "Youngstedt, O'Connor & Dishman (1997). The Effects of Acute Exercise on Sleep: A Quantitative Synthesis. Sleep. ~329 citations.",
        "content": (
            "This meta-analysis of 38 studies found modest but reliable improvements in sleep "
            "outcomes after acute exercise, including total sleep time and slow-wave sleep. "
            "It showed that timing and duration of exercise matter, and replaced anecdote-heavy "
            "discussion with pooled effect sizes. Regular aerobic and resistance exercise "
            "consistently improves sleep quality, but vigorous exercise within 1–2 hours of "
            "bedtime may delay sleep onset in some individuals due to elevated core body "
            "temperature and cortisol."
        ),
    },
    {
        "topic": "Stress, Cortisol, and Sleep Architecture",
        "citation": "Van Reeth et al. (2000). Interactions Between Stress and Sleep: From Basic Research to Clinical Situations. Sleep Medicine Reviews.",
        "content": (
            "This review synthesises human and animal work showing that both acute and chronic "
            "stress can reshape sleep architecture and circadian rhythms through HPA-axis and "
            "sympathoadrenal activation. It frames stress and sleep as bidirectional — poor sleep "
            "raises cortisol, elevated cortisol disrupts sleep. Stress-related sleep disruption "
            "manifests as increased sleep onset latency, more frequent awakenings, and reduced "
            "deep sleep. High evening stress scores on wearables are predictive of reduced "
            "overnight HRV and lower sleep scores the following morning."
        ),
    },
    {
        "topic": "Chronic Insomnia, HPA Axis, and Cortisol Hyperarousal",
        "citation": "Vgontzas et al. (2001). Chronic Insomnia Is Associated with Nyctohemeral Activation of the Hypothalamic-Pituitary-Adrenal Axis. Journal of Clinical Endocrinology & Metabolism. ~790 citations.",
        "content": (
            "This paper is one of the most cited demonstrations that chronic poor sleep is "
            "associated with elevated ACTH and cortisol secretion, particularly in the evening "
            "and first half of the night. It shifted understanding of insomnia away from 'simply "
            "not enough sleep' toward a disorder of hyperarousal with measurable endocrine "
            "consequences. This framing has shaped later sleep biomarker work and explains why "
            "stress reduction is a core evidence-based intervention for improving sleep quality."
        ),
    },
    {
        "topic": "Blue Light, Melatonin, and Circadian Timing",
        "citation": "Chang et al. (2015). Evening Use of Light-Emitting eReaders Negatively Affects Sleep, Circadian Timing, and Next-Morning Alertness. PNAS.",
        "content": (
            "In a controlled crossover study, evening use of a light-emitting eReader delayed "
            "circadian timing, suppressed evening sleepiness, and worsened next-morning alertness "
            "compared with reading a printed book. Short-wavelength blue light suppresses melatonin "
            "secretion by up to 85% and delays the body clock. This paper tied light spectrum, "
            "melatonin, sleep timing, and next-day function together, becoming the standard reference "
            "for why screen use before bed is biologically active disruption, not merely distraction. "
            "Avoiding screens 60–90 minutes before bed is the evidence-based recommendation."
        ),
    },
    {
        "topic": "Sleep Regularity and Circadian Alignment",
        "citation": "Phillips et al. (2017). Irregular Sleep/Wake Patterns Are Associated with Poorer Academic Performance and Delayed Circadian and Sleep/Wake Timing. Scientific Reports. ~577 citations.",
        "content": (
            "This paper introduced the Sleep Regularity Index in a real-world study and showed "
            "that irregular sleepers had later circadian phase, weaker day-night rhythms, and "
            "worse performance outcomes. Crucially, sleep regularity is partly separable from "
            "sleep duration — the same number of hours at inconsistent times produces worse "
            "outcomes. Even 30–60 minutes of inconsistency in sleep timing measurably impairs "
            "next-day alertness. Going to bed and waking at the same time daily is as important "
            "as total sleep duration."
        ),
    },
    {
        "topic": "Alcohol and Sleep Architecture",
        "citation": "Ebrahim et al. (2013). Alcohol and Sleep I: Effects on Normal Sleep. Alcoholism: Clinical and Experimental Research.",
        "content": (
            "This review synthesises the alcohol and sleep literature showing the classic biphasic "
            "pattern: shorter sleep latency and consolidated first-half sleep, followed by second-half "
            "disruption, fragmentation, and poorer continuity. Alcohol suppresses REM sleep and "
            "increases awakenings in the second half of the night as the body metabolises it. "
            "Even moderate consumption (1–2 drinks) measurably reduces sleep quality. "
            "Garmin sleep scores reliably detect alcohol-affected nights through elevated resting HR "
            "and reduced HRV — even when total sleep duration appears adequate."
        ),
    },
    {
        "topic": "Sleep Duration and Immune Function — Infection Susceptibility",
        "citation": "Cohen et al. (2009). Sleep Habits and Susceptibility to the Common Cold. Archives of Internal Medicine.",
        "content": (
            "This viral-challenge study is one of the cleanest demonstrations that shorter sleep "
            "and poorer sleep efficiency predict greater susceptibility to respiratory infection. "
            "People sleeping under 7 hours were significantly more likely to develop a cold when "
            "exposed to rhinovirus compared to those sleeping 8+ hours, with low sleep efficiency "
            "an even stronger predictor. It links habitual sleep directly to a real infectious "
            "outcome rather than a proxy biomarker — a single night of sleep loss reduces natural "
            "killer cell activity by up to 70%."
        ),
    },
    {
        "topic": "Sleep and Immune Function — Adaptive Immunity",
        "citation": "Besedovsky, Lange & Born (2012). Sleep and Immune Function. Pflügers Archiv – European Journal of Physiology. ~916 citations.",
        "content": (
            "This review synthesises evidence that sleep — especially early-night slow-wave-sleep-rich "
            "sleep — promotes a pro-inflammatory but immune-consolidating endocrine milieu with high "
            "growth hormone and prolactin and low cortisol and catecholamines. Sleep preferentially "
            "supports initiation of adaptive immune responses and formation of immunological memory. "
            "Vaccination efficacy is reduced by up to 50% in sleep-deprived individuals. "
            "This is one of the most-cited modern reviews connecting sleep architecture, circadian "
            "biology, and host immune defence."
        ),
    },
    # ── Training and recovery (added for the merged Itri app) ─────────────
    {
        "topic": "Sleep Extension and Athletic Performance — Basketball",
        "citation": "Mah, Mah, Kezirian & Dement (2011). The Effects of Sleep Extension on the Athletic Performance of Collegiate Basketball Players. Sleep, 34(7), 943–950.",
        "content": (
            "Collegiate basketball players extended their sleep, aiming for 10 hours in bed each night, for "
            "5–7 weeks after a baseline period of their normal sleep. Sprint times got faster and shooting "
            "accuracy improved (free throws and three-pointers each by roughly 9%), alongside better reported "
            "mood and less daytime sleepiness. It is a small study, but one of the clearest demonstrations "
            "that athletes carrying a sleep debt gain skill and speed from more sleep."
        ),
    },
    {
        "topic": "Sleep Loss and Exercise Performance — Review",
        "citation": "Fullagar, Skorski, Duffield, Hammes, Coutts & Meyer (2015). Sleep and Athletic Performance: The Effects of Sleep Loss on Exercise Performance, and Physiological and Cognitive Responses to Exercise. Sports Medicine, 45(2), 161–186.",
        "content": (
            "This review found that sleep loss most consistently harms prolonged and submaximal exercise, "
            "skill execution and cognitive performance (reaction time, decision making), while effects on "
            "single maximal efforts such as strength are smaller and less consistent. Perceived effort tends "
            "to rise after poor sleep. For stop-start skill sports like tennis or squash, the cognitive and "
            "skill effects are the most relevant."
        ),
    },
    {
        "topic": "Evening Exercise and Sleep — Meta-Analysis",
        "citation": "Stutz, Eiholzer & Spengler (2019). Effects of Evening Exercise on Sleep in Healthy Participants: A Systematic Review and Meta-Analysis. Sports Medicine, 49(2), 269–287.",
        "content": (
            "Across 23 studies, exercise in the evening did not impair sleep overall, and was linked to "
            "slightly more deep sleep. The exception was vigorous exercise ending within about an hour "
            "of bedtime, which delayed falling asleep and was linked to lower sleep efficiency. Practical "
            "reading: evening training is fine, but leave time to wind down after hard sessions."
        ),
    },
    {
        "topic": "HRV-Guided Training",
        "citation": "Kiviniemi, Hautala, Kinnunen & Tulppo (2007). Endurance Training Guided Individually by Daily Heart Rate Variability Measurements. European Journal of Applied Physiology, 101(6), 743–751.",
        "content": (
            "Participants either followed a fixed training plan or had each day's intensity chosen from "
            "their morning HRV: hard training when HRV was normal or high, easy training or rest when it "
            "had dropped. The HRV-guided group improved aerobic fitness more than the fixed-plan group. "
            "It is the origin of 'train hard when HRV is in range, ease off when it is below'."
        ),
    },
    {
        "topic": "Monitoring HRV Trends in Athletes",
        "citation": "Plews, Laursen, Stanley, Kilding & Buchheit (2013). Training Adaptation and Heart Rate Variability in Elite Endurance Athletes: Opening the Door to Effective Monitoring. Sports Medicine, 43(9), 773–781.",
        "content": (
            "Single-day HRV readings are noisy, so this paper recommends following a rolling average "
            "(about 7 days) and comparing it with the athlete's own normal range. A sustained fall below "
            "the usual range suggests accumulating fatigue, while day-to-day swings on their own mean "
            "little. HRV is best read against the individual's own baseline, not population norms."
        ),
    },
    {
        "topic": "Heart Rate Measures for Monitoring Training Status",
        "citation": "Buchheit (2014). Monitoring Training Status with HR Measures: Do All Roads Lead to Rome? Frontiers in Physiology, 5, 73.",
        "content": (
            "This review explains how resting heart rate, HRV and heart-rate recovery after exercise can "
            "track fitness and fatigue, and why they must be read in context: a change can mean improved "
            "fitness or accumulated fatigue depending on what training preceded it. A faster drop in heart "
            "rate after hard efforts generally reflects better fitness, while a raised resting heart rate "
            "over several days is a common early sign of fatigue or illness."
        ),
    },
    {
        "topic": "Sleep in Elite Athletes",
        "citation": "Halson (2014). Sleep in Elite Athletes and Nutritional Interventions to Enhance Sleep. Sports Medicine, 44(Suppl 1), S13–S23.",
        "content": (
            "Athletes often sleep less and less efficiently than they need, especially around late "
            "training, travel and competition. The review summarises practical levers: regular sleep and "
            "wake times, a cool dark room, limiting caffeine and alcohol, and some nutritional approaches "
            "with early evidence. It frames sleep as part of training, not separate from it."
        ),
    },
]


def embed_with_rate_limit(vectorstore, documents, batch_size=10, pause=3):
    """Add documents in small batches with backoff for Gemini's free-tier quota (100 req/min)."""
    total = len(documents)
    for i in range(0, total, batch_size):
        batch = documents[i:i + batch_size]
        last_error = None
        for attempt in range(6):
            try:
                vectorstore.add_documents(batch)
                break
            except Exception as e:
                last_error = e
                if "RESOURCE_EXHAUSTED" in str(e) or "429" in str(e):
                    wait = 45
                    print(f"  Rate limited, waiting {wait}s (attempt {attempt + 1})...")
                    time.sleep(wait)
                else:
                    raise
        else:
            raise RuntimeError(f"Gave up after repeated rate-limit retries. Last error: {last_error}")
        print(f"  Embedded {min(i + batch_size, total)}/{total} papers")
        time.sleep(pause)


def _reset_collection(client):
    """(Re)create the Qdrant collection empty. This is a Qdrant admin call — it doesn't
    touch Gemini at all, so it isn't subject to the embedding rate limit."""
    if client.collection_exists(COLLECTION_NAME):
        client.delete_collection(COLLECTION_NAME)
    client.create_collection(
        collection_name=COLLECTION_NAME,
        vectors_config=VectorParams(size=EMBEDDING_SIZE, distance=Distance.COSINE),
    )


def ingest_research():
    print(f"Embedding {len(RESEARCH_PAPERS)} peer-reviewed sleep and training papers...")

    documents = []
    for paper in RESEARCH_PAPERS:
        text = (
            f"Topic: {paper['topic']}\n"
            f"Citation: {paper['citation']}\n\n"
            f"{paper['content']}"
        )
        doc = Document(
            page_content=text,
            metadata={
                "topic": paper["topic"],
                "citation": paper["citation"],
                "type": "research",
            },
        )
        documents.append(doc)
        print(f"  ✓ {paper['topic']}")

    client = QdrantClient(url=QDRANT_URL, api_key=QDRANT_API_KEY)
    _reset_collection(client)

    embeddings = GoogleGenerativeAIEmbeddings(model="models/gemini-embedding-001")
    vectorstore = QdrantVectorStore(client=client, collection_name=COLLECTION_NAME, embedding=embeddings)
    embed_with_rate_limit(vectorstore, documents)

    print(f"\n✅ Done. {len(documents)} papers stored in Qdrant collection '{COLLECTION_NAME}'")


if __name__ == "__main__":
    ingest_research()
