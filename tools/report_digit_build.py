"""Record the actual bitstream, source hashes, resource/timing report and test logs."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output-dir',default='outflow_digits_5plus2')
args=parser.parse_args()
out=ROOT/args.output_dir
bit=out/'ti60f225_oob.bit'
report=ET.parse(out/'ti60f225_oob.route.rpt.xml').getroot()
ns={'e':'http://www.efinixinc.com/tool_report'}
groups={g.attrib['name']:{d.attrib['name']:d.attrib.get('value') for d in g}
        for g in report.findall('e:group',ns)}
sources=['rtl/ti60f225_oob_top.v','rtl_custom/ui_ctrl.v','rtl_custom/display_split_2px.v',
         'rtl_custom/digit_capture_2px.v','rtl_custom/digit_match_7p2.v',
         'rtl_custom/digit_outline_2px.v','rtl_custom/digit_result_overlay_2px.v',
         'rtl_custom/digit_result_control.v',
         'digit_7p2_templates.mem','digit_standard_spans.mem','digit_results.mem','ti60f225_oob.xml']
tests=['tb_ui_menu','tb_bank_switch_freeze','tb_display_split_2px','tb_digit_match',
       'tb_digit_capture','tb_digit_pipeline','tb_digit_live_result','tb_digit_result_control','tb_digit_answer_pixels','tb_digit_video']
logs={}
for test in tests:
    path=ROOT/'sim/build/digits'/f'{test}.log'
    if path.exists():
        text=path.read_text(errors='replace')
        logs[test]={'pass':'PASS' in text and '** Fatal:' not in text and '# Errors: 0, Warnings: 0' in text,
                    'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
data={'build_report_date':report.attrib['date'],'mode':'live 7/5 + 2, computed sum, standard outlines, 18-frame answer delay',
      'bitstream':bit.name,'bitstream_bytes':bit.stat().st_size,
      'bitstream_sha256':hashlib.sha256(bit.read_bytes()).hexdigest(),
      'resources':groups['Core Resources'],'timing_final':groups['Timing (Final)'],
      'source_sha256':{s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources},
      'available_test_logs':logs,'hardware_tested':False}
video=ROOT/'sim/build/digits/video_verification.json'
if video.exists():
    data['video_verification']=json.loads(video.read_text())
(out/'verification.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
print(json.dumps({k:data[k] for k in ['bitstream_bytes','bitstream_sha256','resources','timing_final']},indent=2))
