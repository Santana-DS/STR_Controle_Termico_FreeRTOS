function [amostras, metricas] = e3a_validar_io_passivo(porta, quantidade, pastaResultados)
%E3A_VALIDAR_IO_PASSIVO Valida ADC real e PWM em zero, sem alimentar a planta.

diretorioScript = fileparts(mfilename('fullpath'));
raizBancada = fileparts(diretorioScript);
assert(isfolder(fullfile(raizBancada, 'firmware', 'str')), ...
    'Estrutura do repositorio invalida: firmware/str nao encontrado.');

if nargin < 1 || strlength(string(porta)) == 0
    porta = "COM3";
end
if nargin < 2 || isempty(quantidade)
    quantidade = 30;
end
if nargin < 3 || strlength(string(pastaResultados)) == 0
    pastaResultados = fullfile(raizBancada, 'resultados', 'reproduzidos', 'e3a');
end

porta = string(porta);
pastaResultados = string(pastaResultados);
assert(quantidade >= 1 && quantidade <= 300 && quantidade == floor(quantidade), ...
    'A quantidade deve ser um inteiro entre 1 e 300.');
if ~isfolder(pastaResultados)
    mkdir(pastaResultados);
end

portasDisponiveis = string(serialportlist("available"));
assert(any(strcmpi(portasDisponiveis, porta)), ...
    'A porta %s nao esta disponivel. Feche o monitor serial.', porta);

sp = serialport(porta, 115200, 'Timeout', 3);
cleanup = onCleanup(@() limparSerial(sp));
configureTerminator(sp, "LF");
pause(1.0);
flush(sp);

writeline(sp, "PING");
pong = aguardarPrefixo(sp, "ACK,PONG,E3A_IO_PREFLIGHT", 5);
assert(pong == "ACK,PONG,E3A_IO_PREFLIGHT", ...
    'Firmware conectado nao e o preflight E3a: %s', pong);

fprintf('\nE3a: preflight passivo com %d amostras na %s.\n', quantidade, porta);
fprintf('Mantenha os 12 V DESLIGADOS. Os dois PWM permanecem em zero.\n\n');
writeline(sp, "START_IO," + string(quantidade));
ack = aguardarPrefixo(sp, "ACK,START_IO,", 5);
assert(ack == "ACK,START_IO," + string(quantidade), ...
    'Confirmacao inesperada do firmware: %s', ack);

linhas = strings(quantidade, 1);
recebidas = 0;
concluido = false;
inicio = tic;
timeoutS = quantidade * 1.25 + 10;
while toc(inicio) < timeoutS && ~(concluido && recebidas >= quantidade)
    if sp.NumBytesAvailable == 0
        pause(0.01);
        continue;
    end
    linha = strtrim(readline(sp));
    if startsWith(linha, "IO,")
        recebidas = recebidas + 1;
        assert(recebidas <= quantidade, 'Foram recebidas amostras excedentes.');
        linhas(recebidas) = linha;
        fprintf('  Amostra %d/%d\n', recebidas, quantidade);
    elseif linha == "DONE,E3A,OUTPUTS_ZERO,1"
        concluido = true;
    elseif startsWith(linha, "ERRO,") || startsWith(linha, "ALARM,")
        error('Firmware reportou erro: %s', linha);
    end
end

assert(recebidas == quantidade, ...
    'Timeout: recebidas %d de %d amostras.', recebidas, quantidade);
assert(concluido, 'O firmware nao confirmou o termino seguro do E3a.');
amostras = converterAmostras(linhas);
metricas = resumir(amostras);

instante = string(datetime('now','Format','yyyy-MM-dd_HHmmss'));
base = instante + "_E3a_r01";
arquivoAmostras = fullfile(pastaResultados, base + "_io.csv");
arquivoMetricas = fullfile(pastaResultados, base + "_metricas.csv");
writetable(amostras, arquivoAmostras);
writetable(metricas, arquivoMetricas);

disp(metricas);
fprintf('Amostras: %s\n', arquivoAmostras);
fprintf('Metricas: %s\n', arquivoMetricas);

assert(isequal(amostras.sequencia, (0:quantidade-1)'), ...
    'Sequencia de amostras inconsistente.');
assert(~any(amostras.jitter_us < 0 | amostras.execucao_us < 0 | ...
    amostras.resposta_us < 0 | amostras.espera_adc_us < 0), ...
    'Foram encontrados tempos negativos.');
assert(~any(amostras.perdeu_deadline), 'O E3a registrou perda de deadline.');
assert(all(amostras.sensores_ok), 'O firmware detectou leitura de sensor invalida.');
assert(all(amostras.saidas_zero) && ...
    all(amostras.pwm_aquecedor == 0) && all(amostras.pwm_ventilador == 0), ...
    'Uma saida PWM deixou o estado seguro zero.');
assert(all(amostras.Tp_C >= 5 & amostras.Tp_C <= 60) && ...
    all(amostras.Ta_C >= 5 & amostras.Ta_C <= 60), ...
    'Temperatura fora da faixa plausivel de 5 a 60 graus C. Verifique a planta.');
assert(max(abs(amostras.Tp_C - amostras.Ta_C)) <= 20, ...
    'Diferenca entre Tp e Ta acima de 20 graus C. Verifique os sensores.');
fprintf('\nE3a APROVADO: ADCs plausiveis, deadline atendido e PWM sempre zero.\n');
end

function linha = aguardarPrefixo(sp, prefixo, timeoutS)
inicio = tic;
while toc(inicio) < timeoutS
    if sp.NumBytesAvailable > 0
        linha = strtrim(readline(sp));
        if startsWith(linha, prefixo)
            return;
        end
    else
        pause(0.01);
    end
end
error('Timeout aguardando %s.', prefixo);
end

function amostras = converterAmostras(linhas)
n = numel(linhas);
valores = zeros(n, 17);
for k = 1:n
    partes = split(linhas(k), ',');
    assert(numel(partes) == 18 && partes(1) == "IO", ...
        'Linha IO invalida: %s', linhas(k));
    numeros = str2double(partes(2:end));
    assert(all(isfinite(numeros)), 'Valor nao numerico: %s', linhas(k));
    valores(k,:) = numeros';
end
amostras = table(valores(:,1), valores(:,2), valores(:,3), valores(:,4), ...
    valores(:,5), valores(:,6), valores(:,7), valores(:,8), logical(valores(:,9)), ...
    valores(:,10), valores(:,11), valores(:,12), valores(:,13), valores(:,14), ...
    logical(valores(:,15)), logical(valores(:,16)), valores(:,17), ...
    'VariableNames', {'sequencia','liberacao_us','inicio_us','termino_us', ...
    'deadline_us','jitter_us','execucao_us','resposta_us','perdeu_deadline', ...
    'Tp_C','Ta_C','pwm_aquecedor','pwm_ventilador','espera_adc_us', ...
    'sensores_ok','saidas_zero','n_leituras_adc'});
end

function metricas = resumir(a)
nomes = ["amostras"; "Tp_media_C"; "Tp_min_C"; "Tp_max_C"; "Tp_dp_C"; ...
    "Ta_media_C"; "Ta_min_C"; "Ta_max_C"; "Ta_dp_C"; ...
    "diferenca_Tp_Ta_max_C"; "execucao_media_us"; "execucao_p95_us"; ...
    "execucao_p99_us"; "execucao_max_us"; "resposta_max_us"; ...
    "jitter_max_us"; "espera_adc_max_us"; "perdas_deadline"; "pwm_nao_zero"];
valores = [height(a); mean(a.Tp_C); min(a.Tp_C); max(a.Tp_C); std(a.Tp_C); ...
    mean(a.Ta_C); min(a.Ta_C); max(a.Ta_C); std(a.Ta_C); ...
    max(abs(a.Tp_C-a.Ta_C)); mean(a.execucao_us); percentil(a.execucao_us,95); ...
    percentil(a.execucao_us,99); max(a.execucao_us); max(a.resposta_us); ...
    max(a.jitter_us); max(a.espera_adc_us); sum(a.perdeu_deadline); ...
    sum(a.pwm_aquecedor ~= 0 | a.pwm_ventilador ~= 0)];
unidades = ["contagem"; repmat("degC",9,1); repmat("us",7,1); ...
    "contagem"; "contagem"];
metricas = table(nomes, valores, unidades, ...
    'VariableNames', {'metrica','valor','unidade'});
end

function valor = percentil(x, p)
x = sort(x(:));
posicao = 1 + (numel(x)-1) * p / 100;
inferior = floor(posicao);
superior = ceil(posicao);
if inferior == superior
    valor = x(inferior);
else
    valor = x(inferior) + (posicao-inferior) * (x(superior)-x(inferior));
end
end

function limparSerial(sp)
try
    writeline(sp, "STOP");
    pause(0.05);
    flush(sp);
catch
end
end
