function resumo = e0_replay_baseline()
%E0_REPLAY_BASELINE Reexecuta o nucleo do PRJ2 com o ensaio final gravado.
%
% O objetivo desta etapa e formar uma referencia dourada independente de
% ADC, PWM, Serial e FreeRTOS. O CSV contem Y arredondado a quatro casas e t
% arredondado a milissegundos; portanto, pequenas diferencas acumuladas sao
% esperadas e devem ser quantificadas, nao escondidas.

arquivoEste = mfilename('fullpath');
pastaMatlab = fileparts(arquivoEste);
raiz = fileparts(pastaMatlab);
entrada = fullfile(raiz, 'resultados', 'traces', 'e0', ...
    'ensaio_controle_refinado.csv');
saida = fullfile(raiz, 'resultados', 'metricas', ...
    'e0_equivalencia_baseline.csv');

assert(isfile(entrada), 'Arquivo de entrada nao encontrado: %s', entrada);
dados = readtable(entrada, 'VariableNamingRule', 'preserve');
esperadas = ["t","R","Y","Ta","W","modo","beta","U_nom", ...
    "U_cool","U_livre","Us","e_sin_nom","e_sin_cool", ...
    "inov_nom","inov_cool"];
assert(all(ismember(esperadas, string(dados.Properties.VariableNames))), ...
    'O CSV nao possui todas as colunas esperadas.');

p = parametros();
n = height(dados);
pred = struct();
nom = struct();
cool = struct();
inicializado = false;
modoCooler = false;
contadorModo = uint8(0);
betaAtual = 1.0;
segmentoAnterior = NaN;
indiceSegmento = 0;

campos = {'R','W','modo','beta','U_nom','U_cool','U_livre','Us', ...
    'e_sin_nom','e_sin_cool','inov_nom','inov_cool'};
for k = 1:numel(campos)
    pred.(campos{k}) = zeros(n,1);
end

for k = 1:n
    segmentoAtual = dados.segmento(k);
    if ~isequal(segmentoAtual, segmentoAnterior)
        inicializado = false;
        modoCooler = false;
        contadorModo = uint8(0);
        betaAtual = 1.0;
        indiceSegmento = 0;
        segmentoAnterior = segmentoAtual;
    end
    tempo = dados.t(k);
    y = dados.Y(k);
    r = referencia(indiceSegmento);

    if ~inicializado
        nom = alinharNominal(y, r, 0.0, p);
        cool = alinharCooler(y, r, 0.0, betaAtual, p);
        inicializado = true;
    end

    w = comandoCooler(tempo, p);
    pedido = (~modoCooler && w >= p.WEntrar) || ...
        (modoCooler && w > p.WSair);
    if pedido == modoCooler
        contadorModo = uint8(0);
    else
        contadorModo = contadorModo + 1;
        if contadorModo >= p.NConfirmacoes
            modoCooler = pedido;
            contadorModo = uint8(0);
        end
    end

    novoBeta = pesoReferenciaCooler(tempo, p);
    if abs(novoBeta - betaAtual) >= 1e-12
        cool.xi = cool.xi + p.NbCool * (betaAtual - novoBeta) * ...
            (r - p.Y0Cool) / p.KiCool;
        betaAtual = novoBeta;
    end

    cn = calcularNominal(nom, r, y, p);
    cc = calcularCooler(cool, r, y, betaAtual, p);
    if modoCooler
        uLivre = cc.uLivre;
    else
        uLivre = cn.uLivre;
    end
    us = min(max(uLivre, 0.0), p.PwmMax);

    if modoCooler
        cool = avancarCooler(cool, cc, r, us, p);
        nom = alinharNominal(y, r, us, p);
    else
        nom = avancarNominal(nom, cn, r, y, us, p);
        cool = alinharCooler(y, r, us, betaAtual, p);
    end

    pred.R(k) = r;
    pred.W(k) = w;
    pred.modo(k) = modoCooler;
    pred.beta(k) = betaAtual;
    pred.U_nom(k) = cn.uLivre;
    pred.U_cool(k) = cc.uLivre;
    pred.U_livre(k) = uLivre;
    pred.Us(k) = round(us); % CSV usa Serial.printf("%.0f").
    pred.e_sin_nom(k) = cn.eSeno;
    pred.e_sin_cool(k) = cc.eSeno;
    pred.inov_nom(k) = cn.inovacao;
    pred.inov_cool(k) = cc.inovacao;
    indiceSegmento = indiceSegmento + 1;
end

nomes = string(campos(:));
maxAbs = zeros(numel(campos),1);
rmse = zeros(numel(campos),1);
mediaAbs = zeros(numel(campos),1);
for k = 1:numel(campos)
    nome = campos{k};
    erro = pred.(nome) - dados.(nome);
    maxAbs(k) = max(abs(erro));
    rmse(k) = sqrt(mean(erro.^2));
    mediaAbs(k) = mean(abs(erro));
end

tolerancia = [0; 0; 0; 0; 1; 1; 1; 1; 0.5; 1; 2e-4; 2e-4];
aprovado = maxAbs <= tolerancia;
resumo = table(nomes, maxAbs, rmse, mediaAbs, tolerancia, aprovado, ...
    'VariableNames', {'sinal','max_abs','rmse','media_abs', ...
    'tolerancia','aprovado'});
writetable(resumo, saida);

fprintf('E0 baseline: %d amostras reexecutadas.\n', n);
disp(resumo);
fprintf('Metricas gravadas em: %s\n', saida);
assert(all(aprovado), ...
    'E0 reprovado: ao menos um sinal excedeu a tolerancia registrada.');
end

function p = parametros()
p.Ts2 = 2.8575;
p.PwmMax = 65535.0;
p.WEntrar = 2000;
p.WSair = 1000;
p.NConfirmacoes = uint8(2);
p.BetaSeno = 0.80;
p.FaseSeno = 2.940997279299572;

p.Y0Nom = 50.50282999999999;
p.U0Nom = 9688.13559322;
p.NbNom = 1615.01542842;
p.KiNom = 55.87486056;
p.K1Nom = 2.42292827;
p.K2Nom = 37.30035107;
p.KqNom = 0.45467056;
p.CsNom = [1.30135744, 5.41983902];
p.GTermico = 455.85236927;
p.Ad1 = 0.97680948204771745;
p.Ad2 = 0.83799947890809312;
p.Bd1 = 0.012391015895003424;
p.Bd2 = 0.011491559879183539;
p.ANom = [ ...
    0.87148850627135255, -2.3349292179027987, 0.012391015895003424, 0; ...
   -0.021460368525439675, 0.36223061019376079, 0.011491559879183539, 0; ...
    0.54700065839072487, 12.12681339185988, 0.84668688848431295, 5.4198390207695537; ...
    0.098868116531183062, 2.1918715840409377, -0.052237956106038111, 0.84668688848431295];
p.BNom = [0.012391015895003424; 0.011491559879183539; 0; 0];
p.LNom = [101.15520303030875; 20.611544085060167; ...
   -525.365078032665; -94.957574473786678];
p.CNom = [0.0010411819918428509, 0.023082640812882287];

p.Y0Cool = 50.0;
p.U0Cool = 29668.6850393701;
p.NbCool = 2157.30127859495;
p.KiCool = 74.6363818007599;
p.KxCool = 9.05232146430076;
p.KqCool = 0.368257902253556;
p.CCool = 0.00533973420046468;
p.CsCool = [1.214944790737869, 5.41983902076955];
p.ACool = [ ...
    0.758025026798745, 0.0389974309184895, 0; ...
    0, 0.846686888484313, 5.41983902076955; ...
    0, -0.0522379561060381, 0.846686888484313];
p.BCool = [0.0389974309184895; 0; 0];
p.LCool = [59.9192070008071; -1100.25874176182; -100.465858001758];
end

function r = referencia(indice)
r = 45.0;
if mod(floor(double(indice) / 70), 2) ~= 0
    r = 55.0;
end
end

function w = comandoCooler(t, p)
if t < 1000.0
    w = 0;
    return;
end
if t < 1800.0 || t >= 3000.0
    w = 3211;
    return;
end
seno = sin(2*pi*(t - 1800.0)/64.0 + p.FaseSeno);
valor = 3051.0 + 803.0*seno;
if t >= 2936.0
    alfa = 0.5*(1.0 + cos(pi*(t - 2936.0)/64.0));
    valor = 3211.0 + alfa*(valor - 3211.0);
end
w = fix(min(max(valor, 2248.0), 3854.0));
end

function beta = pesoReferenciaCooler(t, p)
beta = 1.0;
if t >= 1800.0 && t < 3000.0
    beta = p.BetaSeno;
end
end

function s = alinharNominal(y, r, us, p)
entrada = (y - p.Y0Nom) * p.GTermico;
s.z = [p.Bd1*entrada/(1-p.Ad1); p.Bd2*entrada/(1-p.Ad2); 0; 0];
s.q = us - p.U0Nom;
s.xi = (us - p.U0Nom - p.NbNom*(r-p.Y0Nom) + ...
    p.K1Nom*s.z(1) + p.K2Nom*s.z(2) + p.KqNom*s.q) / p.KiNom;
s.erroAnterior = r-y;
s.referenciaAnterior = r;
s.correcaoAnterior = 0;
end

function s = alinharCooler(y, r, us, beta, p)
s.z = [(y-p.Y0Cool)/p.CCool; 0; 0];
s.q = us-p.U0Cool;
s.xi = (us-p.U0Cool-p.NbCool*beta*(r-p.Y0Cool) + ...
    p.KxCool*s.z(1)+p.KqCool*s.q)/p.KiCool;
s.erroAnterior = r-y;
s.referenciaAnterior = r;
s.correcaoAnterior = 0;
end

function c = calcularNominal(s, r, y, p)
c.erro = r-y;
c.xi = s.xi + p.Ts2*(s.erroAnterior+s.referenciaAnterior-y) + ...
    s.correcaoAnterior;
c.eSeno = p.CsNom*s.z(3:4);
yEstimado = p.CNom*s.z(1:2);
c.uLivre = p.U0Nom+p.NbNom*(r-p.Y0Nom)+p.KiNom*c.xi - ...
    p.K1Nom*s.z(1)-p.K2Nom*s.z(2)-p.KqNom*s.q-c.eSeno;
c.inovacao = y-p.Y0Nom-yEstimado;
end

function c = calcularCooler(s, r, y, beta, p)
c.erro = r-y;
c.xi = s.xi+p.Ts2*(s.erroAnterior+s.referenciaAnterior-y) + ...
    s.correcaoAnterior;
c.eSeno = p.CsCool*s.z(2:3);
c.uLivre = p.U0Cool+p.NbCool*beta*(r-p.Y0Cool)+p.KiCool*c.xi - ...
    p.KxCool*s.z(1)-p.KqCool*s.q-c.eSeno;
c.inovacao = y-p.Y0Cool-p.CCool*s.z(1);
end

function s = avancarNominal(s, c, r, y, us, p)
s.z = p.ANom*s.z+p.BNom*s.q+p.LNom*(y-p.Y0Nom);
s.xi = c.xi;
s.erroAnterior = c.erro;
s.referenciaAnterior = r;
s.correcaoAnterior = (us-c.uLivre)/p.KiNom;
s.q = us-p.U0Nom;
end

function s = avancarCooler(s, c, r, us, p)
s.z = p.ACool*s.z+p.BCool*s.q+p.LCool*c.inovacao;
s.xi = c.xi;
s.erroAnterior = c.erro;
s.referenciaAnterior = r;
s.correcaoAnterior = (us-c.uLivre)/p.KiCool;
s.q = us-p.U0Cool;
end
