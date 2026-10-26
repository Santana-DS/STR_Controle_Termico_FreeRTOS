function [eventos, resumo, trace] = e8_coletar_matriz_falhas(porta, repeticoes, pastaResultados, mostrarGrafico)
%E8_COLETAR_MATRIZ_FALHAS Valida cinco caminhos de desligamento seguro.

diretorioScript = fileparts(mfilename('fullpath'));
raizBancada = fileparts(diretorioScript);
assert(isfolder(fullfile(raizBancada, 'firmware', 'str')), ...
    'Estrutura do repositorio invalida: firmware/str nao encontrado.');

if nargin < 1 || strlength(string(porta)) == 0
    porta = "COM3";
end
if nargin < 2 || isempty(repeticoes)
    repeticoes = 5;
end
if nargin < 3 || strlength(string(pastaResultados)) == 0
    pastaResultados = fullfile(raizBancada, 'resultados', 'reproduzidos', 'e8');
end
if nargin < 4 || isempty(mostrarGrafico)
    mostrarGrafico = true;
end

porta = string(porta);
pastaResultados = string(pastaResultados);
assert(repeticoes >= 1 && repeticoes == floor(repeticoes));
assert(islogical(mostrarGrafico) && isscalar(mostrarGrafico));
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
statusFinal = "";

writeline(sp, "PING");
[pong, linhas] = aguardarPrefixo(sp, "ACK,PONG,E8_FAULT_MATRIX", 5, linhas);
assert(pong == "ACK,PONG,E8_FAULT_MATRIX", ...
    'Firmware conectado nao e o E8: %s', pong);

fprintf('\nE8: matriz de falhas com %d repeticoes por caminho.\n', repeticoes);
fprintf('Mantenha os 12 V desligados durante todo o ensaio.\n\n');

for k = 1:repeticoes
    linhas = prepararRepeticao(sp, linhas);
    antes = contarTarefa(linhas, "ATUA_STOP");
    [~, linhas] = enviarEAguardar(sp, "STOP", "ACK,STOP", 5, linhas);
    linhas = aguardarNovaTarefa(sp, "ATUA_STOP", antes, 5, linhas);
    [statusFinal, linhas] = consultarEstadoSeguro(sp, linhas);
    fprintf('  STOP %d/%d.\n', k, repeticoes);
end

for k = 1:repeticoes
    linhas = prepararRepeticao(sp, linhas);
    antesDet = contarTarefa(linhas, "DET_SENSOR");
    antesAtua = contarTarefa(linhas, "ATUA_SAFE");
    [~, linhas] = enviarEAguardar(sp, "INJECT,SENSOR", ...
        "ACK,INJECT,SENSOR,", 5, linhas);
    linhas = aguardarNovaTarefa(sp, "DET_SENSOR", antesDet, 5, linhas);
    linhas = aguardarNovaTarefa(sp, "ATUA_SAFE", antesAtua, 5, linhas);
    [statusFinal, linhas] = consultarEstadoSeguro(sp, linhas);
    fprintf('  SENSOR_INVALIDO %d/%d.\n', k, repeticoes);
end

for k = 1:repeticoes
    linhas = prepararRepeticao(sp, linhas);
    antesDet = contarTarefa(linhas, "DET_TEMP");
    antesAtua = contarTarefa(linhas, "ATUA_SAFE");
    [~, linhas] = enviarEAguardar(sp, "INJECT,TEMP", ...
        "ACK,INJECT,TEMP,", 5, linhas);
    linhas = aguardarNovaTarefa(sp, "DET_TEMP", antesDet, 5, linhas);
    linhas = aguardarNovaTarefa(sp, "ATUA_SAFE", antesAtua, 5, linhas);
    [statusFinal, linhas] = consultarEstadoSeguro(sp, linhas);
    fprintf('  SOBRETEMPERATURA %d/%d.\n', k, repeticoes);
end

for k = 1:repeticoes
    linhas = prepararRepeticao(sp, linhas);
    antesDet = contarTarefa(linhas, "DET_HB");
    antesAtua = contarTarefa(linhas, "ATUA_HB");
    fprintf('  HEARTBEAT %d/%d: aguardando timeout de 15 s...\n', ...
        k, repeticoes);
    linhas = aguardarNovaTarefa(sp, "DET_HB", antesDet, 18, linhas);
    linhas = aguardarNovaTarefa(sp, "ATUA_HB", antesAtua, 5, linhas);
    [statusFinal, linhas] = consultarEstadoSeguro(sp, linhas);
end

fprintf('\nPressione e solte BOOT somente quando solicitado.\n');
for k = 1:repeticoes
    linhas = prepararRepeticao(sp, linhas);
    antes = contarTarefa(linhas, "ATUA_EMERG");
    fprintf('>>> BOOT agora (%d/%d).\n', k, repeticoes);
    linhas = aguardarBootComHeartbeat(sp, antes, 30, linhas);
    [statusFinal, linhas] = consultarEstadoSeguro(sp, linhas);
end

trace = converterTrace(linhas);
eventos = montarEventos(trace, repeticoes);
resumo = resumirEventos(eventos);

instante = string(datetime('now','Format','yyyy-MM-dd_HHmmss'));
base = fullfile(pastaResultados, instante + "_E8_r01");
writetable(eventos, base + "_eventos.csv");
writetable(resumo, base + "_metricas.csv");
writetable(trace, base + "_trace.csv");

fid = fopen(base + "_integridade.txt", 'w');
assert(fid >= 0, 'Nao foi possivel criar o arquivo de integridade.');
fecharArquivo = onCleanup(@() fclose(fid));
fprintf(fid, 'status_final=%s\n', statusFinal);
fprintf(fid, 'repeticoes_por_falha=%d\n', repeticoes);
fprintf(fid, 'eventos_totais=%d\n', height(eventos));
clear fecharArquivo

validarResultado(eventos, resumo, trace, statusFinal, repeticoes);
plotarResumo(resumo, base + "_falhas.png", mostrarGrafico);

disp(resumo);
fprintf('\nE8 APROVADO: cinco caminhos levaram os PWM ao estado seguro.\n');
fprintf('Eventos:  %s\n', base + "_eventos.csv");
fprintf('Metricas: %s\n', base + "_metricas.csv");
fprintf('Trace:    %s\n', base + "_trace.csv");
end

function linhas = prepararRepeticao(sp, linhas)
[~, linhas] = enviarEAguardar(sp, "ARM", "ACK,ARM", 5, linhas);
[~, linhas] = enviarEAguardar(sp, "ARM_HB", "ACK,ARM_HB", 5, linhas);
[~, linhas] = enviarEAguardar(sp, "HEARTBEAT", "ACK,HEARTBEAT", 5, linhas);
[~, linhas] = enviarEAguardar(sp, "START,60", "ACK,START,60", 5, linhas);
pause(0.8);
end

function [status, linhas] = consultarEstadoSeguro(sp, linhas)
pause(0.10);
writeline(sp, "STATUS");
[status, linhas] = aguardarPrefixo(sp, "STATUS,E8,", 5, linhas);
partes = split(status, ',');
assert(numel(partes) == 17 && partes(3) == "0" && partes(4) == "1" && ...
    partes(7) == "0" && partes(8) == "0", ...
    'Estado final inseguro: %s', status);
end

function [resposta, linhas] = enviarEAguardar(sp, comando, prefixo, timeoutS, linhas)
writeline(sp, comando);
[resposta, linhas] = aguardarPrefixo(sp, prefixo, timeoutS, linhas);
end

function [resposta, linhas] = aguardarPrefixo(sp, prefixo, timeoutS, linhas)
inicio = tic;
while toc(inicio) < timeoutS
    if sp.NumBytesAvailable == 0
        pause(0.01);
        continue;
    end
    linha = strtrim(readline(sp));
    if startsWith(linha, "TRACE,")
        linhas(end+1,1) = linha; %#ok<AGROW>
    end
    if startsWith(linha, prefixo)
        resposta = linha;
        return;
    end
end
error('Timeout aguardando %s.', prefixo);
end

function linhas = aguardarNovaTarefa(sp, tarefa, quantidadeAntes, timeoutS, linhas)
inicio = tic;
while contarTarefa(linhas, tarefa) <= quantidadeAntes
    if toc(inicio) >= timeoutS
        error('Timeout aguardando %s.', tarefa);
    end
    if sp.NumBytesAvailable == 0
        pause(0.01);
        continue;
    end
    linha = strtrim(readline(sp));
    if startsWith(linha, "TRACE,")
        linhas(end+1,1) = linha; %#ok<AGROW>
    end
end
end

function linhas = aguardarBootComHeartbeat(sp, quantidadeAntes, timeoutS, linhas)
% Evita que a demora humana transforme o caso BOOT em falha de heartbeat.
inicio = tic;
ultimoHeartbeat = tic;
while contarTarefa(linhas, "ATUA_EMERG") <= quantidadeAntes
    if toc(inicio) >= timeoutS
        error('Timeout aguardando ATUA_EMERG.');
    end
    if toc(ultimoHeartbeat) >= 4
        writeline(sp, "HEARTBEAT");
        ultimoHeartbeat = tic;
    end
    if sp.NumBytesAvailable == 0
        pause(0.01);
        continue;
    end
    linha = strtrim(readline(sp));
    if startsWith(linha, "TRACE,")
        linhas(end+1,1) = linha; %#ok<AGROW>
    end
end
end

function n = contarTarefa(linhas, tarefa)
n = sum(startsWith(linhas, "TRACE," + tarefa + ","));
end

function trace = converterTrace(linhas)
n = numel(linhas);
tarefa = strings(n,1);
valores = zeros(n,15);
validas = false(n,1);
for k = 1:n
    partes = split(linhas(k), ',');
    if numel(partes) ~= 17 || partes(1) ~= "TRACE"
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
    logical(valores(:,12)), valores(:,13), valores(:,14), valores(:,15), ...
    'VariableNames', {'tarefa','sequencia','liberacao_us','inicio_us', ...
    'termino_us','deadline_us','jitter_us','execucao_us','resposta_us', ...
    'perdeu_deadline','resposta_fim_a_fim_us','deadline_fim_a_fim_us', ...
    'perdeu_deadline_fim_a_fim','bloqueio_us','ocupacao_fila_trace', ...
    'descartes_trace'});
end

function eventos = montarEventos(trace, repeticoes)
tipos = [repmat("STOP",repeticoes,1); ...
    repmat("SENSOR_INVALIDO",repeticoes,1); ...
    repmat("SOBRETEMPERATURA",repeticoes,1); ...
    repmat("HEARTBEAT",repeticoes,1); repmat("BOOT",repeticoes,1)];
repeticao = repmat((1:repeticoes)',5,1);
deteccaoUs = zeros(5*repeticoes,1);
atuacaoUs = zeros(5*repeticoes,1);
deadlineUs = zeros(5*repeticoes,1);

[deteccaoUs(1:repeticoes), atuacaoUs(1:repeticoes), ...
    deadlineUs(1:repeticoes)] = extrairPar(trace,"SUP_STOP","ATUA_STOP",0,repeticoes);
inicio = repeticoes + 1;
fim = 2*repeticoes;
[deteccaoUs(inicio:fim), atuacaoUs(inicio:fim), deadlineUs(inicio:fim)] = ...
    extrairPar(trace,"DET_SENSOR","ATUA_SAFE",0,repeticoes);
inicio = 2*repeticoes + 1;
fim = 3*repeticoes;
[deteccaoUs(inicio:fim), atuacaoUs(inicio:fim), deadlineUs(inicio:fim)] = ...
    extrairPar(trace,"DET_TEMP","ATUA_SAFE",repeticoes,repeticoes);
inicio = 3*repeticoes + 1;
fim = 4*repeticoes;
[deteccaoUs(inicio:fim), atuacaoUs(inicio:fim), deadlineUs(inicio:fim)] = ...
    extrairPar(trace,"DET_HB","ATUA_HB",0,repeticoes);
inicio = 4*repeticoes + 1;
fim = 5*repeticoes;
atuacaoBoot = ordenarPorSequencia(trace(trace.tarefa == "ATUA_EMERG",:));
assert(height(atuacaoBoot) == repeticoes, 'Quantidade de BOOT inconsistente.');
deteccaoUs(inicio:fim) = 0;
atuacaoUs(inicio:fim) = atuacaoBoot.resposta_fim_a_fim_us;
deadlineUs(inicio:fim) = atuacaoBoot.deadline_fim_a_fim_us;

eventos = table(tipos,repeticao,deteccaoUs,atuacaoUs,deadlineUs, ...
    'VariableNames', {'falha','repeticao','deteccao_us','atuacao_total_us', ...
    'deadline_us'});
end

function [detUs, atuaUs, deadlineUs] = extrairPar(trace,tarefaDet,tarefaAtua,offset,n)
det = trace(trace.tarefa == tarefaDet,:);
atua = trace(trace.tarefa == tarefaAtua & ...
    trace.sequencia >= offset & trace.sequencia < offset+n,:);
det = det(det.sequencia >= offset & det.sequencia < offset+n,:);
det = ordenarPorSequencia(det);
atua = ordenarPorSequencia(atua);
assert(height(det) == n && height(atua) == n, ...
    'Quantidade inconsistente para %s/%s.', tarefaDet, tarefaAtua);
detUs = det.resposta_fim_a_fim_us;
atuaUs = atua.resposta_fim_a_fim_us;
deadlineUs = atua.deadline_fim_a_fim_us;
end

function t = ordenarPorSequencia(t)
[~,ordem] = sort(t.sequencia);
t = t(ordem,:);
end

function resumo = resumirEventos(eventos)
falha = unique(eventos.falha,'stable');
n = numel(falha);
repeticoes = zeros(n,1);
mediaUs = zeros(n,1);
p95Us = zeros(n,1);
p99Us = zeros(n,1);
maxUs = zeros(n,1);
deadlineUs = zeros(n,1);
for k = 1:n
    x = eventos.atuacao_total_us(eventos.falha == falha(k));
    repeticoes(k) = numel(x);
    mediaUs(k) = mean(x);
    p95Us(k) = percentil(x,95);
    p99Us(k) = percentil(x,99);
    maxUs(k) = max(x);
    deadlineUs(k) = max(eventos.deadline_us(eventos.falha == falha(k)));
end
resumo = table(falha,repeticoes,mediaUs,p95Us,p99Us,maxUs,deadlineUs, ...
    'VariableNames', {'falha','repeticoes','latencia_media_us', ...
    'latencia_p95_us','latencia_p99_us','latencia_max_us','deadline_us'});
end

function validarResultado(eventos,resumo,trace,status,repeticoes)
assert(height(eventos) == 5*repeticoes && ...
    all(resumo.repeticoes == repeticoes));
assert(all(eventos.atuacao_total_us >= 0) && ...
    all(eventos.atuacao_total_us <= eventos.deadline_us), ...
    'Uma falha excedeu sua deadline de atuacao segura.');
assert(~any(trace.perdeu_deadline | trace.perdeu_deadline_fim_a_fim), ...
    'O trace registrou perda de deadline.');
assert(isempty(trace) || max(trace.descartes_trace) == 0, ...
    'O trace registrou descarte.');
partes = split(status, ',');
assert(partes(3) == "0" && partes(7) == "0" && partes(8) == "0", ...
    'Status final inseguro: %s', status);
end

function plotarResumo(resumo,arquivo,mostrar)
visibilidade = 'off';
if mostrar
    visibilidade = 'on';
end
fig = figure('Color','w','Visible',visibilidade,'Name','E8 - matriz de falhas');
bar([resumo.latencia_media_us resumo.latencia_p95_us ...
    resumo.latencia_max_us]/1000,'grouped');
grid on;
ylabel('Latência até PWM zero (ms)');
title('E8 — atuação segura por tipo de falha');
xticks(1:height(resumo));
xticklabels(strrep(resumo.falha,'_',' '));
legend({'Média','P95','Máximo'},'Location','northwest');
exportgraphics(fig,arquivo,'Resolution',180);
if ~mostrar
    close(fig);
end
end

function valor = percentil(x,p)
x = sort(x(:));
assert(~isempty(x));
posicao = 1 + (numel(x)-1)*p/100;
inferior = floor(posicao);
superior = ceil(posicao);
if inferior == superior
    valor = x(inferior);
else
    valor = x(inferior) + (posicao-inferior)*(x(superior)-x(inferior));
end
end

function limparSerial(sp)
try
    writeline(sp,"STOP");
    pause(0.05);
    flush(sp);
catch
end
end
