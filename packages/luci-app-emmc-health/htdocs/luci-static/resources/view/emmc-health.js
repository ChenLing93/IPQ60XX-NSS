'use strict';
'require view';
'require fs';
'require poll';

return view.extend({
	load: function() {
		return fs.exec('/usr/bin/emmc-health');
	},

	render: function(res) {
		var self = this;

		var out = E('pre', {
			'style': 'white-space:pre-wrap;font-family:monospace;margin:0;padding:12px;' +
				'background:rgba(0,0,0,.03);border-radius:6px;font-size:13px;line-height:1.5'
		}, String((res && (res.stdout || res.stderr)) || '(没有输出：这台机器可能不是 eMMC)').trim());

		var status = E('span', { 'class': 'ifacebadge' }, _('最近一次检测结果'));

		var btn = E('button', {
			'class': 'cbi-button cbi-button-action',
			'click': function() {
				btn.disabled = true;
				return fs.exec('/usr/bin/emmc-health').then(function(r) {
					out.textContent = String((r && (r.stdout || r.stderr)) || '(没有输出)').trim();
				}).catch(function(e) {
					out.textContent = _('执行失败') + '：' + e;
				}).finally(function() {
					btn.disabled = false;
				});
			}
		}, _('重新检测'));

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('eMMC 健康 / 寿命')),
			E('div', { 'class': 'cbi-map-descr' },
				_('数据来自 eMMC 的 EXT_CSD：Pre-EOL（寿命预警）、寿命估计 A/B、累计写入量、CRC 错误。') + ' ' +
				_('Pre-EOL 出现 0x02/0x03 或寿命估计超过 0x09 就该考虑换盘备份了。')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'style': 'margin-bottom:10px' }, [ status, ' ', btn ]),
				out
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
