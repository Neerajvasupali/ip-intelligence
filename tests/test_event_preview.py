import copy,json,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from validate_events import preview,MAX_BYTES
ROOT=Path(__file__).resolve().parents[1]
class EventPreviewTests(unittest.TestCase):
 def setUp(self):self.data=json.loads((ROOT/'demo/repeated_failures.json').read_text())
 def call(self,data):return preview(json.dumps(data).encode())
 def test_valid(self):self.assertTrue(self.call(self.data)['can_import'])
 def test_duplicate(self):self.data['events']*=2;self.assertEqual(sum(r['status']=='duplicate' for r in self.call(self.data)['rows']),3)
 def test_conflict(self):e=copy.deepcopy(self.data['events'][0]);e['outcome']='success';self.data['events'].append(e);self.assertFalse(self.call(self.data)['can_import'])
 def test_invalid_types(self):
  for e in [None,{}, {'event_id':[]},'text']:
   self.data['events']=[e];self.assertFalse(self.call(self.data)['can_import'])
 def test_oversized(self):
  with self.assertRaises(ValueError):preview(b' '*(MAX_BYTES+1))
 def test_batch_limit(self):
  self.data['events']*=34
  with self.assertRaises(ValueError):self.call(self.data)
 def test_non_utc(self):self.data['events'][0]['occurred_at']='2026-01-01T10:00:00+05:30';self.assertFalse(self.call(self.data)['can_import'])
if __name__=='__main__':unittest.main()
