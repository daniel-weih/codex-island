#!/usr/bin/python3
"""Deterministic app-server fixture; never contacts Codex or the network."""
import json, os, sys, time
mode = os.environ.get('RESET_FIXTURE_MODE', 'success')

def emit(x):
    print(json.dumps(x), flush=True)

def note(method, p):
    emit({'method': method, 'params': p})
for line in sys.stdin:
    m = json.loads(line)
    method = m.get('method')
    rid = m.get('id')
    p = m.get('params', {})
    if rid is None:
        continue
    if method == 'initialize':
        r = {}
    elif method == 'account/read':
        r = {'account': {'type': 'chatgpt'}}
    elif method == 'model/list':
        if not p.get('cursor'):
            r = {'data': [{'model': 'other', 'displayName': 'Other', 'supportedReasoningEfforts': [{'reasoningEffort': 'low'}]}], 'nextCursor': 'page2'}
        else:
            r = {'data': [{'model': 'gpt-6-sol', 'displayName': 'GPT-6 Sol', 'supportedReasoningEfforts': [{'reasoningEffort': 'max'}], 'serviceTiers': [{'id': 'fast', 'name': 'Fast'}]}], 'nextCursor': None}
    elif method == 'config/read':
        r = {'config': {'mcp_servers': {'a.b': {'enabled': True}}, 'plugins': {'plug@test': {'enabled': True}}, 'apps': {'a': {'enabled': True}}}}
    elif method == 'thread/start':
        assert p['config']['mcp_servers']['a.b']['enabled'] is False
        assert p['config']['apps']['a']['enabled'] is False
        assert p['config']['features.shell_tool'] is False
        assert p['config']['features.fast_mode'] == (p['serviceTier'] == 'fast')
        r = {'thread': {'id': 'fixture-thread', 'ephemeral': True}, 'model': p['model'], 'reasoningEffort': p['config']['model_reasoning_effort'], 'serviceTier': p['serviceTier'], 'sandbox': {'type': 'readOnly'}, 'approvalPolicy': 'never', 'instructionSources': []}
    elif method == 'fixture/hang':
        continue
    elif method == 'turn/start':
        assert p['outputSchema']['additionalProperties'] is False
        if mode == 'pending':
            time.sleep(30)
            continue
        r = {'turn': {'id': 'fixture-turn', 'status': 'inProgress', 'items': []}}
        if mode == 'approval':
            emit({'id': rid, 'method': 'item/commandExecution/requestApproval', 'params': {'threadId': 'fixture-thread'}})
        emit({'id': rid, 'result': r})
        note('thread/tokenUsage/updated', {'threadId': 'fixture-thread', 'turnId': 'fixture-turn', 'tokenUsage': {'total': {'inputTokens': 100, 'cachedInputTokens': 25, 'outputTokens': 50, 'reasoningOutputTokens': 20, 'totalTokens': 150}}})
        if mode == 'timeout':
            time.sleep(30)
            continue
        if mode == 'approval':
            continue
        if mode == 'reroute':
            note('model/rerouted', {'threadId': 'fixture-thread', 'turnId': 'fixture-turn', 'toModel': 'other'})
            continue
        if mode == 'failed':
            note('turn/completed', {'threadId': 'fixture-thread', 'turn': {'id': 'fixture-turn', 'status': 'failed', 'items': [], 'error': {'message': 'fixture failure'}}})
            continue
        out = {'title': '补发备用重置', 'summary': '据来源正在补发一次备用重置', 'applicability': None, 'kind': 'banked', 'status': 'announced', 'scheduledAt': None, 'timeDescription': None, 'evidence': 'source says credit', 'timeEvidence': None}
        if mode == 'invented':
            out.update(scheduledAt='2026-09-25T22:00:00+08:00', timeEvidence='soon')
        if mode == 'explicit-date':
            payload = json.loads(p['input'][0]['text'].split('\n', 1)[1])
            out.update(status='scheduled', scheduledAt='2026-09-25T14:00:00Z', timeEvidence=payload['sourceText'])
        note('item/completed', {'threadId': 'fixture-thread', 'turnId': 'fixture-turn', 'item': {'id': 'answer', 'type': 'agentMessage', 'phase': 'final_answer', 'text': json.dumps(out)}})
        note('turn/completed', {'threadId': 'fixture-thread', 'turn': {'id': 'fixture-turn', 'status': 'completed', 'items': []}})
        continue
    else:
        r = {}
    emit({'id': rid, 'result': r})
