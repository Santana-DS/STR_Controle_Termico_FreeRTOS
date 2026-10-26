function [trace, resumo] = e1_coletar_timing(porta, duracaoS, repeticao, pastaResultados)
%E1_COLETAR_TIMING Coleta e resume o trace temporal do runner FreeRTOS E1.

diretorioScript = fileparts(mfilename('fullpath'));
raizBancada = fileparts(diretorioScript);
assert(isfolder(fullfile(raizBancada, 'firmware', 'str')), ...
    'Estrutura do repositorio invalida: firmware/str nao encontrado.');

if nargin < 1 || strlength(string(porta)) == 0
    porta = "COM3";
end
if nargin < 2 || isempty(duracaoS)
    duracaoS = 120;
end
if nargin < 3 || isempty(repeticao)
    repeticao = 1;
end
if nargin < 4 || strlength(string(pastaResultados)) == 0
    pastaResultados = fullfile(raizBancada, 'resultados', 'reproduzidos', 'e1');
end

porta = string(porta);
pastaResultados = string(pastaResultados);
assert(duracaoS > 0, 'A duracao deve ser positiva.');
assert(repeticao >= 1 && repeticao == floor(repeticao), ...
    'A repeticao deve ser um inteiro positivo.');
if ~isfolder(pastaResultados)
    mkdir(pastaResultados);
end

portasDisponiveis = string(serialportlist("available"));
assert(any(strcmpi(portasDisponiveis, porta)), ...
    'A porta %s nao esta disponivel. Feche o monitor serial e reconecte a ESP32.', porta);

fprintf('E1 temporal: %.0f s, repeticao %d, porta %s.\n', ...
    duracaoS, repeticao, porta);
sp = serialport(porta, 115200, 'Timeout', 3);
cleanup = onCleanup(@() limparSerial(sp));
configureTerminator(sp, "LF");
pause(1.0);
flush(sp);

writeline(sp, "PING");
pong = aguardarPrefixo(sp, "ACK,PONG,E1_TIMING", 5);
assert(pong == "ACK,PONG,E1_TIMING", ...
    'Firmware conectado nao e o runner E1: %s', pong);

writeline(sp, "START");
ack = aguardarPrefixo(sp, "ACK,START", 5);
assert(startsWith(ack, "ACK,START"), 'START nao confirmado: %s', ack);

linhas = strings(0,1);
inicio = tic;
proximoAviso = 60;
while toc(inicio) < duracaoS
    if sp.NumBytesAvailable > 0
        linha = strtrim(readline(sp));
        if startsWith(linha, "TRACE,")
            linhas(end+1,1) = linha; %#ok<AGROW>
        end
    else
        pause(0.01);
    end
    decorrido = toc(inicio);
    if decorrido >= proximoAviso
        fprintf('  %.0f/%.0f s; %d registros recebidos.\n', ...
            decorrido, duracaoS, numel(linhas));
        proximoAviso = proximoAviso + 60;
    end
end

writeline(sp, "STOP");
fimDrenagem = tic;
while toc(fimDrenagem) < 2
    if sp.NumBytesAvailable > 0
        linha = strtrim(readline(sp));
        if startsWith(linha, "TRACE,")
            linhas(end+1,1) = linha; %#ok<AGROW>
        end
    else
        pause(0.01);
    end
end
writeline(sp, "STATUS");
status = aguardarPrefixo(sp, "STATUS,", 5);

trace = converterTrace(linhas);
resumo = resumirTrace(trace);

instante = string(datetime('now','Format','yyyy-MM-dd_HHmmss'));
base = instante + "_E1_r" + compose('%02d', repeticao);
arquivoTrace = fullfile(pastaResultados, base + "_trace.csv");
arquivoMetricas = fullfile(pastaResultados, base + "_metricas.csv");
writetable(trace, arquivoTrace);
writetable(resumo, arquivoMetricas);

disp(resumo);
fprintf('Status final: %s\n', status);
fprintf('Trace: %s\n', arquivoTrace);
fprintf('Metricas: %s\n', arquivoMetricas);

assert(height(trace) > 0, 'Nenhum registro TRACE foi recebido.');
assert(~any(trace.jitter_us < 0) && ~any(trace.resposta_us < 0), ...
    ['Trace temporal inconsistente: jitter ou resposta negativa. ' ...
    'Revise a referencia de liberacao.']);
assert(~any(trace.perdeu_deadline), ...
    'O E1 registrou perda de deadline local.');
assert(~any(trace.perdeu_deadline_fim_a_fim), ...
    'O E1 registrou perda de deadline fim a fim.');
assert(max(trace.descartes_trace) == 0, ...
    'O E1 registrou descarte de telemetria.');
fprintf('E1 aprovado: %d registros, sem perdas de deadline ou trace.\n', ...
    height(trace));
end

function trace = converterTrace(linhas)
n = numel(linhas);
tarefa = strings(n,1);
valores = zeros(n,14);
validas = false(n,1);
for k = 1:n
    partes = split(linhas(k), ',');
    if numel(partes) ~= 16 || partes(1) ~= "TRACE"
        continue;
    end
    numeros = str2double(partes(3:end));
    if any(~isfinite(numeros))
        continue;
    end
    tarefa(k) = partes(2);
    valores(k,:) = numeros';
    validas(k) = true;
end
tarefa = tarefa(validas);
valores = valores(validas,:);
trace = table(tarefa, valores(:,1), valores(:,2), valores(:,3), ...
    valores(:,4), valores(:,5), valores(:,6), valores(:,7), valores(:,8), ...
    logical(valores(:,9)), valores(:,10), valores(:,11), ...
    logical(valores(:,12)), valores(:,13), valores(:,14), ...
    'VariableNames', {'tarefa','sequencia','liberacao_us','inicio_us', ...
    'termino_us','deadline_us','jitter_us','execucao_us','resposta_us', ...
    'perdeu_deadline','resposta_fim_a_fim_us','deadline_fim_a_fim_us', ...
    'perdeu_deadline_fim_a_fim','ocupacao_fila_trace','descartes_trace'});
end

function resumo = resumirTrace(trace)
tarefas = unique(trace.tarefa, 'stable');
n = numel(tarefas);
jobs = zeros(n,1);
jitterMedio = zeros(n,1);
jitterP95 = zeros(n,1);
jitterMax = zeros(n,1);
execMedio = zeros(n,1);
execP95 = zeros(n,1);
execP99 = zeros(n,1);
execMax = zeros(n,1);
respostaMax = zeros(n,1);
perdas = zeros(n,1);
e2eMax = nan(n,1);
perdasE2e = zeros(n,1);
for k = 1:n
    selecao = trace.tarefa == tarefas(k);
    jobs(k) = sum(selecao);
    jitter = trace.jitter_us(selecao);
    execucao = trace.execucao_us(selecao);
    jitterMedio(k) = mean(jitter);
    jitterP95(k) = percentil(jitter, 95);
    jitterMax(k) = max(jitter);
    execMedio(k) = mean(execucao);
    execP95(k) = percentil(execucao, 95);
    execP99(k) = percentil(execucao, 99);
    execMax(k) = max(execucao);
    respostaMax(k) = max(trace.resposta_us(selecao));
    perdas(k) = sum(trace.perdeu_deadline(selecao));
    e2e = trace.resposta_fim_a_fim_us(selecao & ...
        trace.deadline_fim_a_fim_us > 0);
    if ~isempty(e2e)
        e2eMax(k) = max(e2e);
    end
    perdasE2e(k) = sum(trace.perdeu_deadline_fim_a_fim(selecao));
end
resumo = table(tarefas, jobs, jitterMedio, jitterP95, jitterMax, ...
    execMedio, execP95, execP99, execMax, respostaMax, perdas, e2eMax, ...
    perdasE2e, 'VariableNames', {'tarefa','jobs','jitter_medio_us', ...
    'jitter_p95_us','jitter_max_us','execucao_media_us','execucao_p95_us', ...
    'execucao_p99_us','execucao_max_us','resposta_max_us', ...
    'perdas_deadline','e2e_max_us','perdas_deadline_e2e'});
end

function valor = percentil(x, p)
x = sort(x(:));
if isempty(x)
    valor = NaN;
    return;
end
posicao = 1 + (numel(x)-1) * p / 100;
inferior = floor(posicao);
superior = ceil(posicao);
if inferior == superior
    valor = x(inferior);
else
    valor = x(inferior) + (posicao-inferior) * ...
        (x(superior)-x(inferior));
end
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
        pause(0.02);
    end
end
error('Timeout aguardando %s', prefixo);
end

function limparSerial(sp)
try
    writeline(sp, "STOP");
    pause(0.05);
    flush(sp);
catch
end
end
