#!/usr/bin/env python3
"""Garmin Connect export -> Itri bundle (assets/private/garmin_bundle.json).

Usage:
  pip3 install fitdecode
  python3 tools/garmin_import.py ~/Desktop/NEWGARMIN

Reads activity FIT files from the export zip, resamples them to 5 s, removes
GPS near every start/finish (and all GPS for court/pitch sports), and adds
Garmin's own load figures so the app's model can be checked against them.
Also reads every night of sleep, overnight HRV with Garmin's personal
baseline, daily resting heart rate, stress and Body Battery for Recovery.
The output holds personal data: assets/private/ is git-ignored.
"""
import glob, io, json, math, os, statistics, sys, zipfile
from datetime import datetime, timedelta, timezone

import fitdecode

DT = 5            # output sample spacing (s)
PAUSE_GAP = 30    # a gap longer than this is a pause, not recorded time
PRIVACY_M = 500   # GPS removed within this distance of start and finish

SPORTS = {        # (FIT sport, sub_sport) -> app sport
    ('running', 'generic'): 'run', ('running', 'treadmill'): 'run',
    ('running', 'trail'): 'run', ('cycling', 'generic'): 'ride',
    ('cycling', 'road'): 'ride', ('walking', 'generic'): 'walk',
    ('training', 'strength_training'): 'strength', ('tennis', 'generic'): 'tennis',
    ('racket', 'padel'): 'padel', ('racket', 'squash'): 'squash',
    ('soccer', 'generic'): 'football',
}
KEEP_ROUTE = {'run', 'ride', 'walk'}
SEMI = 180 / 2 ** 31


def one(pattern):
    hits = glob.glob(pattern, recursive=True)
    if not hits:
        sys.exit(f'Not found: {pattern}')
    return hits[0]


def read_fit(data):
    records, session, first = [], None, None
    with fitdecode.FitReader(io.BytesIO(data), check_crc=fitdecode.CrcCheck.DISABLED) as r:
        for fr in r:
            if not isinstance(fr, fitdecode.FitDataMessage):
                continue
            if fr.name == 'file_id' and fr.get_value('type', fallback=None) != 'activity':
                return None, None
            if fr.name == 'record':
                records.append({f.name: f.value for f in fr.fields if f.value is not None})
            elif fr.name == 'session' and session is None:
                session = {f.name: f.value for f in fr.fields if f.value is not None}
    return records, session


def resample(records, sport):
    """Collapse pauses, then average into DT-second buckets."""
    pts, t, prev = [], 0.0, None
    for r in records:
        ts = r.get('timestamp')
        if ts is None:
            continue
        if prev is not None:
            gap = (ts - prev).total_seconds()
            t += DT if gap > PAUSE_GAP else gap
        prev = ts
        cad = r.get('cadence')
        if cad is not None and sport == 'run':
            cad = (cad + (r.get('fractional_cadence') or 0)) * 2   # strides -> steps
        elif sport != 'run':
            cad = None
        lat, lon = r.get('position_lat'), r.get('position_long')
        pts.append(dict(t=t, hr=r.get('heart_rate'), d=r.get('distance'),
                        v=r.get('enhanced_speed', r.get('speed')),
                        alt=r.get('enhanced_altitude', r.get('altitude')),
                        lat=lat * SEMI if isinstance(lat, int) else None,
                        lon=lon * SEMI if isinstance(lon, int) else None,
                        cad=cad, pw=r.get('power')))
    if not pts:
        return []
    out, bucket, edge = [], [], DT

    def mean(k):
        vals = [p[k] for p in bucket if p[k] is not None]
        return sum(vals) / len(vals) if vals else None

    def flush():
        if not bucket:
            return
        last_d = next((p['d'] for p in reversed(bucket) if p['d'] is not None), None)
        out.append(dict(t=int(bucket[0]['t'] // DT * DT), hr=mean('hr'), d=last_d, v=mean('v'),
                        alt=mean('alt'), lat=mean('lat'), lon=mean('lon'), cad=mean('cad'), pw=mean('pw')))

    for p in pts:
        while p['t'] >= edge:
            flush()
            bucket, edge = [], edge + DT
        bucket.append(p)
    flush()
    end = pts[-1]
    out.append(dict(out[-1], t=max(out[-1]['t'] + 1, int(round(end['t'])))))  # closing sample
    return out


def privacy(samples, sport):
    if sport not in KEEP_ROUTE:
        for s in samples:
            s['lat'] = s['lon'] = None
        return
    total = next((s['d'] for s in reversed(samples) if s['d'] is not None), 0) or 0
    for s in samples:
        d = s['d']
        if d is None or d < PRIVACY_M or d > total - PRIVACY_M:
            s['lat'] = s['lon'] = None


def trimp(samples, rest, mx):
    load = 0.0
    for a, b in zip(samples, samples[1:]):
        if a['hr'] is None:
            continue
        hrr = min(max((a['hr'] - rest) / (mx - rest), 0), 1)
        load += (b['t'] - a['t']) / 60 * hrr * 0.64 * math.exp(1.92 * hrr)
    return load


def columns(samples):
    def col(k, nd):
        vals = [s[k] for s in samples]
        if all(v is None for v in vals):
            return None
        return [None if v is None else (round(v) if nd == 0 else round(v, nd)) for v in vals]

    cols = {'t': [s['t'] for s in samples], 'hr': col('hr', 0), 'd': col('d', 1), 'v': col('v', 2),
            'alt': col('alt', 1), 'lat': col('lat', 5), 'lon': col('lon', 5), 'cad': col('cad', 0),
            'pw': col('pw', 0)}
    return {k: v for k, v in cols.items() if v is not None}


def gmt_to_local(ts, offset_s):
    """'2026-01-29T01:09:19.0' (GMT) + offset -> naive local ISO string."""
    t = datetime.fromisoformat(ts.split('.')[0])
    return (t + timedelta(seconds=offset_s)).isoformat(timespec='minutes')


def load_recovery(di):
    """Nights and days for the Recovery half. Keys are the calendar date Garmin
    files a night under, which is the morning you wake up."""
    days, offsets = {}, {}
    for f in sorted(glob.glob(f'{di}/DI-Connect-Aggregator/UDSFile_*.json')):
        for d in json.load(open(f)):
            date = d['calendarDate']
            try:
                loc = datetime.fromisoformat(d['wellnessStartTimeLocal'].split('.')[0])
                gmt = datetime.fromisoformat(d['wellnessStartTimeGmt'].split('.')[0])
                offsets[date] = int((loc - gmt).total_seconds())
            except (KeyError, TypeError, ValueError):
                pass
            stress = next((a.get('averageStressLevel') for a in (d.get('allDayStress') or {}).get('aggregatorList', [])
                           if a.get('type') == 'AWAKE'), None)
            bb = {x['bodyBatteryStatType']: x['statsValue'] for x in (d.get('bodyBattery') or {}).get('bodyBatteryStatList', [])}
            day = {'rhr': d.get('restingHeartRate'), 'stress': stress if stress and stress > 0 else None,
                   'steps': d.get('totalSteps'), 'bbHigh': bb.get('HIGHEST'), 'bbLow': bb.get('LOWEST')}
            day = {k: v for k, v in day.items() if v is not None}
            if day:
                days[date] = day

    hrv = {}
    for f in sorted(glob.glob(f'{di}/DI-Connect-Wellness/*_healthStatusData.json')):
        for d in json.load(open(f)):
            for m in d.get('metrics', []):
                if m.get('type') == 'HRV' and m.get('value'):
                    hrv[d['calendarDate']] = (m['value'], m.get('baselineLowerLimit') or None, m.get('baselineUpperLimit') or None)

    nights = []
    for f in sorted(glob.glob(f'{di}/DI-Connect-Wellness/*_sleepData.json')):
        for n in json.load(open(f)):
            if 'sleepStartTimestampGMT' not in n or not n.get('sleepScores'):
                continue
            date = n['calendarDate']
            off = offsets.get(date, 0)
            sc = n['sleepScores']
            night = {
                'date': date,
                'start': gmt_to_local(n['sleepStartTimestampGMT'], off),
                'end': gmt_to_local(n['sleepEndTimestampGMT'], off),
                'deep': n.get('deepSleepSeconds'), 'light': n.get('lightSleepSeconds'),
                'rem': n.get('remSleepSeconds'), 'awake': n.get('awakeSleepSeconds'),
                'score': sc.get('overallScore'),
                'sub': {k: sc[k] for k in ('qualityScore', 'durationScore', 'recoveryScore', 'deepScore', 'remScore',
                                           'lightScore', 'restfulnessScore', 'interruptionsScore') if sc.get(k) is not None},
                'feedback': sc.get('feedback'),
                'resp': n.get('averageRespiration'), 'stress': n.get('avgSleepStress'),
                'restless': n.get('restlessMomentCount'), 'awakenings': n.get('awakeCount'),
            }
            if date in hrv:
                night['hrv'], night['hrvLow'], night['hrvHigh'] = hrv[date]
            day = days.get(date, {})
            if 'rhr' in day:
                night['rhr'] = day['rhr']
            nights.append({k: v for k, v in night.items() if v is not None})
    nights.sort(key=lambda x: x['date'])
    # Nights are keyed by date; the export can repeat a night across files.
    nights = list({n['date']: n for n in nights}.values())
    return nights, days


def pearson(x, y):
    mx, my = statistics.fmean(x), statistics.fmean(y)
    sxy = sum((a - mx) * (b - my) for a, b in zip(x, y))
    return sxy / math.sqrt(sum((a - mx) ** 2 for a in x) * sum((b - my) ** 2 for b in y))


def ranks(v):
    order = sorted(range(len(v)), key=lambda i: v[i])
    r = [0] * len(v)
    for pos, i in enumerate(order):
        r[i] = pos
    return r


def main(root, out_path):
    di = os.path.join(root, 'DI_CONNECT')
    summ = json.load(open(one(f'{di}/DI-Connect-Fitness/*_summarizedActivities.json')))[0]['summarizedActivitiesExport']
    by_start = {int(a['beginTimestamp']): a for a in summ}
    zones = json.load(open(one(f'{di}/DI-Connect-Wellness/*_heartRateZones.json')))[0]
    profile = json.load(open(one(f'{di}/DI-Connect-User/user_profile.json')))
    rhr = {}
    for f in sorted(glob.glob(f'{di}/DI-Connect-Aggregator/UDSFile_*.json')):
        for d in json.load(open(f)):
            if d.get('restingHeartRate'):
                rhr[d['calendarDate']] = d['restingHeartRate']
    weights = [(b['metaData']['calendarDate'], b['weight']['weight'] / 1000)
               for b in json.load(open(one(f'{di}/DI-Connect-Wellness/*_userBioMetrics.json')))
               if isinstance(b.get('weight'), dict) and b['weight'].get('weight')]

    max_hr = int(zones.get('maxHeartRateUsed') or 200)
    rest_hr = int(round(statistics.median(list(rhr.values())[-60:]))) if rhr else int(zones.get('restingHeartRateUsed') or 60)
    weight = round(sorted(weights)[-1][1], 1) if weights else 75.0

    activities, skipped = [], 0
    for zp in sorted(glob.glob(f'{di}/DI-Connect-Uploaded-Files/*.zip')):
        with zipfile.ZipFile(zp) as z:
            for name in z.namelist():
                if not name.endswith('.fit'):
                    continue
                records, sess = read_fit(z.read(name))
                if not sess:
                    continue
                sport = SPORTS.get((str(sess.get('sport')), str(sess.get('sub_sport'))))
                start = sess['start_time']
                meta = by_start.get(int(start.replace(tzinfo=timezone.utc).timestamp() * 1000)) if start.tzinfo is None \
                    else by_start.get(int(start.timestamp() * 1000))
                if sport is None or len(records) < 10:
                    skipped += 1
                    continue
                samples = resample(records, sport)
                if len(samples) < 3:
                    skipped += 1
                    continue
                privacy(samples, sport)
                local = datetime.fromtimestamp(meta['startTimeLocal'] / 1000, tz=timezone.utc).replace(tzinfo=None) \
                    if meta else start.replace(tzinfo=None)
                activities.append({
                    'id': int(meta['activityId']) if meta else int(start.timestamp()),
                    'sport': sport,
                    'indoor': str(sess.get('sub_sport')) == 'treadmill',
                    'name': (meta or {}).get('name') or sport.title(),
                    'start': local.isoformat(timespec='seconds'),
                    'locality': (meta or {}).get('locationName') or '',
                    'calories': sess.get('total_calories'),
                    'garminLoad': round(sess['training_load_peak'], 1) if 'training_load_peak' in sess else None,
                    'aerobicTE': sess.get('total_training_effect'),
                    'anaerobicTE': sess.get('total_anaerobic_training_effect'),
                    's': columns(samples),
                    '_trimp': trimp(samples, rest_hr, max_hr),
                })
    activities.sort(key=lambda a: a['start'], reverse=True)

    pairs = [(a['_trimp'], a['garminLoad']) for a in activities if a['garminLoad']]
    r = pearson(*zip(*pairs))
    rho = pearson(ranks([p[0] for p in pairs]), ranks([p[1] for p in pairs]))
    per_sport = {}
    for sp in sorted({a['sport'] for a in activities}):
        ps = [(a['_trimp'], a['garminLoad']) for a in activities if a['sport'] == sp and a['garminLoad']]
        if len(ps) >= 5:
            per_sport[sp] = {'n': len(ps), 'r': round(pearson(*zip(*ps)), 3)}
    for a in activities:
        del a['_trimp']

    nights, days = load_recovery(di)

    bundle = {
        'version': 2,
        'source': 'Garmin Connect export',
        'exportedAt': max([a['start'][:10] for a in activities] + [n['date'] for n in nights]),
        'athlete': {'name': profile.get('firstName') or 'Athlete', 'maxHr': max_hr, 'restHr': rest_hr,
                    'weightKg': weight, 'birthYear': int(profile['birthDate'][:4]) if profile.get('birthDate') else None},
        'restingHr': rhr,
        'validation': {'n': len(pairs), 'pearson': round(r, 3), 'spearman': round(rho, 3), 'bySport': per_sport},
        'activities': activities,
        'nights': nights,
        'days': days,
    }
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, 'w') as f:
        json.dump(bundle, f, separators=(',', ':'))
    print(f'{len(activities)} activities ({skipped} skipped) -> {out_path} '
          f'({os.path.getsize(out_path) / 1e6:.1f} MB)')
    print(f'athlete: max {max_hr}, rest {rest_hr}, {weight} kg')
    print(f'recovery: {len(nights)} nights ({sum(1 for n in nights if "hrv" in n)} with HRV), {len(days)} days')
    print(f'load vs Garmin: pearson {r:.3f}, spearman {rho:.3f}, n={len(pairs)}; by sport {per_sport}')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    here = os.path.dirname(os.path.abspath(__file__))
    main(os.path.expanduser(sys.argv[1]),
         sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, '..', 'assets', 'private', 'garmin_bundle.json'))
