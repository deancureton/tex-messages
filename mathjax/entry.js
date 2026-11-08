import { mathjax } from 'mathjax-full/js/mathjax.js';
import { TeX } from 'mathjax-full/js/input/tex.js';
import { SVG } from 'mathjax-full/js/output/svg.js';
import { liteAdaptor } from 'mathjax-full/js/adaptors/liteAdaptor.js';
import { RegisterHTMLHandler } from 'mathjax-full/js/handlers/html.js';
import 'mathjax-full/js/input/tex/base/BaseConfiguration.js';
import 'mathjax-full/js/input/tex/ams/AmsConfiguration.js';
import 'mathjax-full/js/input/tex/amscd/AmsCdConfiguration.js';
import 'mathjax-full/js/input/tex/boldsymbol/BoldsymbolConfiguration.js';
import 'mathjax-full/js/input/tex/braket/BraketConfiguration.js';
import 'mathjax-full/js/input/tex/cancel/CancelConfiguration.js';
import 'mathjax-full/js/input/tex/cases/CasesConfiguration.js';
import 'mathjax-full/js/input/tex/centernot/CenternotConfiguration.js';
import 'mathjax-full/js/input/tex/color/ColorConfiguration.js';
import 'mathjax-full/js/input/tex/extpfeil/ExtpfeilConfiguration.js';
import 'mathjax-full/js/input/tex/gensymb/GensymbConfiguration.js';
import 'mathjax-full/js/input/tex/mathtools/MathtoolsConfiguration.js';
import 'mathjax-full/js/input/tex/mhchem/MhchemConfiguration.js';
import 'mathjax-full/js/input/tex/textmacros/TextMacrosConfiguration.js';
import 'mathjax-full/js/input/tex/upgreek/UpgreekConfiguration.js';

const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);

const tex = new TeX({
  packages: ['base', 'ams', 'amscd', 'boldsymbol', 'braket', 'cancel', 'cases',
    'centernot', 'color', 'extpfeil', 'gensymb', 'mathtools', 'mhchem',
    'textmacros', 'upgreek'],
  maxMacros: 500,
  maxBuffer: 20 * 1024,
  formatError: (_, err) => { throw err; },
});
const svg = new SVG({ fontCache: 'none' });
const doc = mathjax.document('', { InputJax: tex, OutputJax: svg });

globalThis.typeset = (source, display) => {
  const node = doc.convert(source, { display });
  return adaptor.innerHTML(node);
};
