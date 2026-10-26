function [trace, resumo] = e2_coletar_seguranca(porta, repeticoesStop, repeticoesEmergencia, pastaResultados)
%E2_COLETAR_SEGURANCA Mede STOP serial e emergencia pelo botao BOOT.

diretorioScript = fileparts(mfilename('fullpath'));
raizBancada = fileparts(diretorioScript);
assert(isfolder(fullfile(raizBancada, 'firmware', 'str')), ...
    'Estrutura do repositorio invalida: firmware/str nao encontrado.');

if nargin < 1 || strlength(string(porta)) == 0
    porta = "COM3";
end
if nargin < 2 || isempty(repeticoesStop)
    repeticoesStop = 20;
end
if nargin < 3 || isempty(repeticoesEmergencia)
    repeticoesEmergencia = 10;
end
if nargin < 4 || strlength(string(pastaResultados)) == 0
    pastaResultados = fullfile(raizBancada, 'resultados', 'reproduzidos', 'e2');
end

porta = string(porta);
pastaResultados = string(pastaResultados);
assert(repeticoesStop >= 1 && repeticoesStop == floor(repeticoesStop));
assert(repeticoesEmergencia >= 1 && ...
    repeticoesEmergencia == floor(repeticoesEmergencia));
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
linhas = strings(0,1);

writeline(sp, "PING");
[pong, linhas] = aguardarPrefixo(sp, "ACK,PONG,E2_SAFETY", 5, linhas);
assert(pong == "ACK,PONG,E2_SAFETY", ...
    'Firmware conectado nao e o runner E2: %s', pong);

fprintf('\nE2: %d repeticoes de STOP por software.\n', repeticoesStop);
for k = 1:repeticoesStop
    [~, linhas] = enviarEAguardar(sp, "START", "ACK,START", 5, linhas);
    pause(0.05);
    quantidadeAntes = contarTarefa(linhas, "ATUA_STOP");
    [~, linhas] = enviarEAguardar(sp, "STOP", "ACK,STOP", 5, linhas);
    linhas = aguardarNovaTarefa(sp, "ATUA_STOP", quantidadeAntes, 5, linhas);
    fprintf('  STOP %d/%d concluido.\n', k, repeticoesStop);
end

fprintf('\nE2: %d repeticoes da emergencia fisica.\n', ...
    repeticoesEmergencia);
fprintf('Pressione rapidamente o botao BOOT somente quando solicitado.\n\n');
for k = 1:repeticoesEmergencia
    [~, linhas] = enviarEAguardar(sp, "ARM", "ACK,ARM", 5, linhas);
    [~, linhas] = enviarEAguardar(sp, "START", "ACK,START", 5, linhas);
    quantidadeAntes = contarTarefa(linhas, "ATUA_EMERG");
    fprintf('>>> Pressione e solte BOOT agora (%d/%d).\n', ...
        k, repeticoesEmergencia);
    linhas = aguardarNovaTarefa(sp, "ATUA_EMERG", quantidadeAntes, 30, linhas);
    fprintf('    Emergencia %d registrada.\n', k);
    pause(0.30);
end

writeline(sp, "STATUS");
[status, linhas] = aguardarPrefixo(sp, "STATUS,", 5, linhas);
trace = converterTrace(linhas);
resumo = resumirSeguranca(trace);

instante = string(datetime('now','Format','yyyy-MM-dd_HHmmss'));
base = instante + "_E2_r01";
arquivoTrace = fullfile(pastaResultados, base + "_trace.csv");
arquivoMetricas = fullfile(pastaResultados, base + "_metricas.csv");
writetable(trace, arquivoTrace);
writetable(resumo, arquivoMetricas);

disp(resumo);
fprintf('Status final: %s\n', status);
fprintf('Trace: %s\n', arquivoTrace);
fprintf('Metricas: %s\n', arquivoMetricas);

assert(contarTarefa(linhas, "ATUA_STOP") == repeticoesStop, ...
    'Quantidade inesperada de atuacoes por STOP.');
assert(contarTarefa(linhas, "SUP_STOP") == repeticoesStop, ...
    'Quantidade inesperada de eventos STOP na supervisao.');
assert(contarTarefa(linhas, "ATUA_EMERG") == repeticoesEmergencia, ...
    'Quantidade inesperada de emergencias fisicas.');
assert(~any(trace.jitter_us < 0) && ~any(trace.resposta_us < 0), ...
    'Trace temporal inconsistente.');
assert(~any(trace.perdeu_deadline) && ...
    ~any(trace.perdeu_deadline_fim_a_fim), ...
    'O E2 registrou perda de deadline.');
assert(max(trace.descartes_trace) == 0, ...
    'O E2 registrou descarte de trace.');
fprintf('E2 aprovado: STOP e emergencia fisica dentro dos deadlines.\n');
end

function [resposta, linhas] = enviarEAguardar(sp, comando, prefixo, timeoutS, linhas)
writeline(sp, comando);
[resposta, linhas] = aguardarPrefixo(sp, prefixo, timeoutS, linhas);
end

function [resposta, linhas] = aguardarPrefixo(sp, prefixo, timeoutS, linhas)
inicio = tic;
while toc(inicio) < timeoutS
    if sp.NumBytesAvailable > 0
        linha = strtrim(readline(sp));
        if startsWith(linha, "TRACE,")
            linhas(end+1,1) = linha; %#ok<AGROW>
        end
        if startsWith(linha, prefixo)
            resposta = linha;
            return;
        end
    else
        pause(0.01);
    end
end
error('Timeout aguardando %s', prefixo);
end

function linhas = aguardarNovaTarefa(sp, tarefa, quantidadeAntes, timeoutS, linhas)
prefixo = "TRACE," + tarefa + ",";
inicio = tic;
while contarTarefa(linhas, tarefa) <= quantidadeAntes
    if toc(inicio) >= timeoutS
        error('Timeout aguardando %s.', tarefa);
    end
    if sp.NumBytesAvailable > 0
        linha = strtrim(readline(sp));
        if startsWith(linha, "TRACE,")
            linhas(end+1,1) = linha; %#ok<AGROW>
        end
    else
        pause(0.01);
    end
end
assert(any(startsWith(linhas, prefixo)));
end

function n = contarTarefa(linhas, tarefa)
n = sum(startsWith(linhas, "TRACE," + tarefa + ","));
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

function resumo = resumirSeguranca(trace)
tarefas = ["ATUA_STOP"; "ATUA_EMERG"];
n = numel(tarefas);
eventos = zeros(n,1);
latenciaMediaUs = zeros(n,1);
latenciaP95Us = zeros(n,1);
latenciaP99Us = zeros(n,1);
latenciaMaxUs = zeros(n,1);
deadlineUs = zeros(n,1);
perdas = zeros(n,1);
for k = 1:n
    selecao = trace.tarefa == tarefas(k);
    latencia = trace.resposta_fim_a_fim_us(selecao);
    eventos(k) = numel(latencia);
    latenciaMediaUs(k) = mean(latencia);
    latenciaP95Us(k) = percentil(latencia, 95);
    latenciaP99Us(k) = percentil(latencia, 99);
    latenciaMaxUs(k) = max(latencia);
    deadlineUs(k) = max(trace.deadline_fim_a_fim_us(selecao));
    perdas(k) = sum(trace.perdeu_deadline_fim_a_fim(selecao));
end
resumo = table(tarefas, eventos, latenciaMediaUs, latenciaP95Us, ...
    latenciaP99Us, latenciaMaxUs, deadlineUs, perdas, ...
    'VariableNames', {'evento','repeticoes','latencia_media_us', ...
    'latencia_p95_us','latencia_p99_us','latencia_max_us','deadline_us', ...
    'perdas_deadline'});
end

function valor = percentil(x, p)
x = sort(x(:));
assert(~isempty(x), 'Nao ha amostras para o percentil.');
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

function limparSerial(sp)
try
    writeline(sp, "STOP");
    pause(0.05);
    flush(sp);
catch
end
end
