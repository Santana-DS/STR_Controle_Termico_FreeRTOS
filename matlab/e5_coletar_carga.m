function [dados, trace, metricas, fases] = e5_coletar_carga(porta, duracaoS, pastaResultados, mostrarGrafico)
%E5_COLETAR_CARGA Mede o caminho critico sob carga progressiva de CPU.

diretorioScript = fileparts(mfilename('fullpath'));
raizBancada = fileparts(diretorioScript);
assert(isfolder(fullfile(raizBancada, 'firmware', 'str')), ...
    'Estrutura do repositorio invalida: firmware/str nao encontrado.');

if nargin < 1 || strlength(string(porta)) == 0
    porta = "COM3";
end
if nargin < 2 || isempty(duracaoS)
    duracaoS = 600;
end
if nargin >= 3
    assert(ischar(pastaResultados) || isstring(pastaResultados), ...
        ['O terceiro argumento deve ser o caminho da pasta de resultados. ' ...
         'Para o E5 use e5_coletar_carga("COM3",600).']);
end
if nargin < 3 || strlength(string(pastaResultados)) == 0
    pastaResultados = fullfile(raizBancada, 'resultados', 'reproduzidos', 'e5');
end
if nargin < 4 || isempty(mostrarGrafico)
    mostrarGrafico = true;
end

porta = string(porta);
pastaResultados = string(pastaResultados);
assert(duracaoS == 600, 'O E5 possui duracao fixa de 600 s.');
assert(islogical(mostrarGrafico) && isscalar(mostrarGrafico), ...
    'mostrarGrafico deve ser true ou false.');
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
pong = aguardarPrefixo(sp, "ACK,PONG,E5_CPU_LOAD", 5);
assert(pong == "ACK,PONG,E5_CPU_LOAD", ...
    'Firmware conectado nao e o E5 de carga: %s', pong);

% Inicializa toda a interface antes de armar o watchdog. Na primeira figura
% de uma sessao, o backend grafico pode levar mais de 15 s para abrir.
monitor = struct();
if mostrarGrafico
    monitor = criarMonitorTempoReal(duracaoS);
end

enviarEAguardar(sp, "ARM", "ACK,ARM", 5);
enviarEAguardar(sp, "ARM_HB", "ACK,ARM_HB", 5);
enviarEAguardar(sp, "HEARTBEAT", "ACK,HEARTBEAT", 5);
enviarEAguardar(sp, "START," + string(duracaoS), ...
    "ACK,START," + string(duracaoS), 5);

fprintf('\nE5: carga progressiva de CPU por %d s na %s.\n', duracaoS, porta);
fprintf('Patamares de 120 s: 0%%, 10%%, 25%%, 40%% e 60%%.\n');
fprintf('Heartbeat automatico a cada 4 s. Nao use monitor serial ou Reset.\n\n');

linhasTrace = strings(0,1);
linhasDados = strings(0,1);
linhasEventos = strings(0,1);
heartbeatsConfirmados = 1;
motivoFim = "";
estadoHeartbeat = struct('porta', sp, 'enviados', 1, 'falha', "");
temporizadorHeartbeat = timer( ...
    'ExecutionMode', 'fixedRate', ...
    'Period', 4, ...
    'StartDelay', 4, ...
    'BusyMode', 'drop', ...
    'TimerFcn', @enviarHeartbeatTemporizado);
temporizadorHeartbeat.UserData = estadoHeartbeat;
limpezaHeartbeat = onCleanup(@() finalizarTemporizador(temporizadorHeartbeat));
start(temporizadorHeartbeat);
inicio = tic;
while toc(inicio) < duracaoS + 30 && strlength(motivoFim) == 0
    estadoHeartbeat = temporizadorHeartbeat.UserData;
    if strlength(estadoHeartbeat.falha) > 0
        error('Falha no temporizador de heartbeat: %s', estadoHeartbeat.falha);
    end

    if sp.NumBytesAvailable == 0
        pause(0.01);
        continue;
    end
    linha = strtrim(readline(sp));
    if startsWith(linha, "TRACE,")
        linhasTrace(end+1,1) = linha; %#ok<AGROW>
    elseif startsWith(linha, "DATA,")
        linhasDados(end+1,1) = linha; %#ok<AGROW>
        partes = split(linha, ',');
        fprintf('  Amostra %s: Tp=%s C, R=%s C, U=%s, W=%s\n', ...
            partes(2), partes(5), partes(4), partes(13), partes(7));
        if mostrarGrafico && isgraphics(monitor.figura)
            atualizarMonitorTempoReal(monitor, partes);
        end
    elseif startsWith(linha, "EVENT,")
        linhasEventos(end+1,1) = linha; %#ok<AGROW>
        if startsWith(linha, "EVENT,END,")
            motivoFim = extractAfter(linha, "EVENT,END,");
        end
    elseif linha == "ACK,HEARTBEAT"
        heartbeatsConfirmados = heartbeatsConfirmados + 1;
    elseif startsWith(linha, "ERRO,")
        error('Firmware reportou erro: %s', linha);
    end
end

stop(temporizadorHeartbeat);
estadoHeartbeat = temporizadorHeartbeat.UserData;
heartbeatsEnviados = estadoHeartbeat.enviados;
assert(strlength(motivoFim) > 0, 'Timeout aguardando o encerramento do E5.');
pause(0.20);
writeline(sp, "STATUS");
[statusFinal, linhasTrace, linhasDados, linhasEventos] = ...
    aguardarPrefixoRegistrando(sp, "STATUS,E5,", 5, ...
    linhasTrace, linhasDados, linhasEventos);
linhasResumo = strings(5,1);
for fase = 0:4
    writeline(sp, "SUMMARY," + string(fase));
    [linhasResumo(fase+1), linhasTrace, linhasDados, linhasEventos] = ...
        aguardarPrefixoRegistrando(sp, "SUMMARY,E5," + string(fase) + ",", 5, ...
        linhasTrace, linhasDados, linhasEventos);
end

dados = converterDados(linhasDados);
trace = converterTrace(linhasTrace);
fases = converterResumosCarga(linhasResumo);
metricas = resumir(dados, trace, heartbeatsEnviados, ...
    heartbeatsConfirmados, motivoFim);

instante = string(datetime('now','Format','yyyy-MM-dd_HHmmss'));
base = instante + "_E5_r01";
arquivoDados = fullfile(pastaResultados, base + "_dados.csv");
arquivoTrace = fullfile(pastaResultados, base + "_trace.csv");
arquivoMetricas = fullfile(pastaResultados, base + "_metricas.csv");
arquivoFases = fullfile(pastaResultados, base + "_fases.csv");
arquivoIntegridade = fullfile(pastaResultados, base + "_integridade.txt");
arquivoMonitor = fullfile(pastaResultados, base + "_monitor.png");
arquivoCarga = fullfile(pastaResultados, base + "_carga.png");
writetable(dados, arquivoDados);
writetable(trace, arquivoTrace);
writetable(metricas, arquivoMetricas);
writetable(fases, arquivoFases);
plotarResumoCarga(fases, arquivoCarga);
if mostrarGrafico && isgraphics(monitor.figura)
    exportgraphics(monitor.figura, arquivoMonitor, 'Resolution', 160);
end
fid = fopen(arquivoIntegridade, 'w');
assert(fid >= 0, 'Nao foi possivel gravar o arquivo de integridade.');
fecharArquivo = onCleanup(@() fclose(fid));
fprintf(fid, 'motivo_fim=%s\n', motivoFim);
fprintf(fid, 'status_final=%s\n', statusFinal);
for k = 1:numel(linhasResumo)
    fprintf(fid, 'summary_fase_%d=%s\n', k-1, linhasResumo(k));
end
fprintf(fid, 'heartbeats_enviados=%d\n', heartbeatsEnviados);
fprintf(fid, 'heartbeats_confirmados=%d\n', heartbeatsConfirmados);
for k = 1:numel(linhasEventos)
    fprintf(fid, '%s\n', linhasEventos(k));
end
clear fecharArquivo

disp(metricas);
disp(fases);
fprintf('Dados: %s\n', arquivoDados);
fprintf('Trace: %s\n', arquivoTrace);
fprintf('Metricas: %s\n', arquivoMetricas);
fprintf('Fases: %s\n', arquivoFases);
fprintf('Integridade: %s\n', arquivoIntegridade);
fprintf('Grafico de carga: %s\n', arquivoCarga);
if mostrarGrafico && isfile(arquivoMonitor)
    fprintf('Grafico: %s\n', arquivoMonitor);
end

quantidadeEsperada = ceil(duracaoS / 5.715);
assert(motivoFim == "FIM_NORMAL", ...
    'E5 encerrado por %s em vez de FIM_NORMAL.', motivoFim);
assert(height(dados) == quantidadeEsperada, ...
    'Esperadas %d amostras; recebidas %d.', quantidadeEsperada, height(dados));
assert(isequal(dados.sequencia, (0:height(dados)-1)'), ...
    'Sequencia funcional inconsistente.');
assert(all(dados.Tp_C >= 5 & dados.Tp_C < 60) && ...
    all(dados.Ta_C >= 5 & dados.Ta_C < 60), ...
    'Temperatura fora da faixa segura de 5 a 60 graus C.');
assert(all(dados.U_saturado >= 0 & dados.U_saturado <= 65535) && ...
    all(dados.W >= 0 & dados.W <= 4095), 'Comando PWM fora da faixa.');
assert(all(dados.atuacao_us >= dados.controle_fim_us & ...
    dados.controle_fim_us >= dados.aquisicao_fim_us & ...
    dados.aquisicao_fim_us >= dados.liberacao_us), ...
    'Precedencia temporal inconsistente nos dados funcionais.');
assert(max(dados.atuacao_us - dados.liberacao_us) <= 5715000, ...
    'Deadline fim a fim perdida nos dados funcionais.');
assert(~any(trace.jitter_us < 0 | trace.execucao_us < 0 | ...
    trace.resposta_us < 0 | trace.bloqueio_us < 0), ...
    'Trace contem tempos negativos.');
assert(~any(trace.perdeu_deadline | trace.perdeu_deadline_fim_a_fim), ...
    'Trace registrou perda de deadline.');
assert(max(trace.descartes_trace) == 0, 'Houve descarte de trace.');
validarTarefa(trace, "AQUISICAO", height(dados));
validarTarefa(trace, "CONTROLE", height(dados));
validarTarefa(trace, "ATUACAO", height(dados));
assert(isequal(fases.carga_pct, [0; 10; 25; 40; 60]), ...
    'Patamares de carga inconsistentes.');
assert(sum(fases.jobs_aquisicao) == quantidadeEsperada && ...
    sum(fases.jobs_controle) == quantidadeEsperada && ...
    sum(fases.jobs_atuacao) == quantidadeEsperada, ...
    'O resumo por fases nao cobre todas as transacoes criticas.');
assert(all(fases.jobs_aquisicao >= 20 & fases.jobs_aquisicao <= 22) && ...
    all(fases.jobs_controle >= 20 & fases.jobs_controle <= 22) && ...
    all(fases.jobs_atuacao >= 20 & fases.jobs_atuacao <= 22), ...
    'Distribuicao inesperada de jobs entre os patamares.');
assert(all(fases.perdas_deadline == 0), ...
    'O resumo por fases registrou perda de deadline.');
assert(all(fases.resposta_aquisicao_max_us <= 600000) && ...
    all(fases.resposta_controle_max_us <= 100000) && ...
    all(fases.resposta_atuacao_max_us <= 20000) && ...
    all(fases.resposta_supervisao_max_us <= 500000) && ...
    all(fases.e2e_max_us <= 5715000), ...
    'Uma fase excedeu deadline local ou fim a fim.');
assert(all(fases.ciclos_carga >= 5000), ...
    'A tarefa de carga executou poucos ciclos em uma fase.');
orcamentoEsperado = fases.ciclos_carga .* 20000 .* fases.carga_pct / 100;
assert(all(fases.orcamento_total_us == orcamentoEsperado), ...
    'O orcamento acumulado da tarefa de carga esta inconsistente.');
assert(sum(startsWith(linhasEventos, "EVENT,CARGA,FASE,")) == 5, ...
    'Nem todos os cinco marcos de carga foram recebidos.');
assert(heartbeatsConfirmados == heartbeatsEnviados, ...
    'Heartbeats confirmados (%d) diferem dos enviados (%d).', ...
    heartbeatsConfirmados, heartbeatsEnviados);
partesStatus = split(statusFinal, ',');
assert(numel(partesStatus) == 17 && partesStatus(3) == "0" && ...
    partesStatus(4) == "1" && partesStatus(7) == "0" && ...
    partesStatus(8) == "0", 'Status final inseguro: %s', statusFinal);
assert(all(str2double(partesStatus(12:17)) == 0), ...
    'O status final registrou descarte interno: %s', statusFinal);
fprintf('\nE5 APROVADO: cinco patamares executados sem perda do caminho critico.\n');
end

function enviarHeartbeatTemporizado(temporizador, ~)
estado = temporizador.UserData;
try
    writeline(estado.porta, "HEARTBEAT");
    estado.enviados = estado.enviados + 1;
catch erro
    estado.falha = string(erro.message);
end
temporizador.UserData = estado;
end

function finalizarTemporizador(temporizador)
if isempty(temporizador) || ~isvalid(temporizador)
    return;
end
if strcmp(temporizador.Running, 'on')
    stop(temporizador);
end
delete(temporizador);
end

function monitor = criarMonitorTempoReal(duracaoS)
monitor.figura = figure('Name', 'E5 - carga progressiva de CPU', ...
    'NumberTitle', 'off', 'Color', 'w');
layout = tiledlayout(monitor.figura, 2, 1, ...
    'TileSpacing', 'compact', 'Padding', 'compact');

monitor.axTemperatura = nexttile(layout);
monitor.referencia = animatedline(monitor.axTemperatura, ...
    'Color', [0.15 0.15 0.15], 'LineStyle', '--', 'LineWidth', 1.5, ...
    'DisplayName', 'Referência');
monitor.Tp = animatedline(monitor.axTemperatura, ...
    'Color', [0.85 0.20 0.15], 'LineWidth', 1.8, 'DisplayName', 'Tp');
monitor.Ta = animatedline(monitor.axTemperatura, ...
    'Color', [0.10 0.45 0.80], 'LineWidth', 1.2, 'DisplayName', 'Ta');
grid(monitor.axTemperatura, 'on');
ylabel(monitor.axTemperatura, 'Temperatura (°C)');
ylim(monitor.axTemperatura, [20 65]);
legend(monitor.axTemperatura, 'Location', 'best');
title(monitor.axTemperatura, 'Aguardando a primeira amostra');
limitesCarga = [120 240 360 480];
rotulosCarga = ["10%" "25%" "40%" "60%"];
for k = 1:numel(limitesCarga)
    xline(monitor.axTemperatura, limitesCarga(k), '--', rotulosCarga(k), ...
        'HandleVisibility', 'off');
end

monitor.axAtuacao = nexttile(layout);
monitor.U = animatedline(monitor.axAtuacao, ...
    'Color', [0.90 0.45 0.10], 'LineWidth', 1.6, ...
    'DisplayName', 'Aquecedor');
monitor.W = animatedline(monitor.axAtuacao, ...
    'Color', [0.25 0.65 0.35], 'LineWidth', 1.6, ...
    'DisplayName', 'Ventilador');
grid(monitor.axAtuacao, 'on');
xlabel(monitor.axAtuacao, 'Tempo (s)');
ylabel(monitor.axAtuacao, 'Comando (% da escala)');
ylim(monitor.axAtuacao, [0 100]);
legend(monitor.axAtuacao, 'Location', 'best');
for k = 1:numel(limitesCarga)
    xline(monitor.axAtuacao, limitesCarga(k), '--', ...
        'HandleVisibility', 'off');
end

limiteInicial = min(300, duracaoS);
xlim(monitor.axTemperatura, [0 limiteInicial]);
xlim(monitor.axAtuacao, [0 limiteInicial]);
sgtitle(layout, sprintf('E5 — carga progressiva no núcleo crítico: %d s', duracaoS));
drawnow;
end

function atualizarMonitorTempoReal(monitor, partes)
tempoS = str2double(partes(3));
referenciaC = str2double(partes(4));
TpC = str2double(partes(5));
TaC = str2double(partes(6));
WPercentual = 100 * str2double(partes(7)) / 4095;
UPercentual = 100 * str2double(partes(13)) / 65535;

addpoints(monitor.referencia, tempoS, referenciaC);
addpoints(monitor.Tp, tempoS, TpC);
addpoints(monitor.Ta, tempoS, TaC);
addpoints(monitor.U, tempoS, UPercentual);
addpoints(monitor.W, tempoS, WPercentual);

limiteX = max(300, 300 * ceil(max(tempoS, 1) / 300));
xlim(monitor.axTemperatura, [0 limiteX]);
xlim(monitor.axAtuacao, [0 limiteX]);
title(monitor.axTemperatura, sprintf( ...
    't = %.1f s | Tp = %.2f °C | referência = %.2f °C', ...
    tempoS, TpC, referenciaC));
drawnow limitrate;
end

function enviarEAguardar(sp, comando, resposta, timeoutS)
writeline(sp, comando);
linha = aguardarPrefixo(sp, resposta, timeoutS);
assert(linha == resposta, 'Resposta inesperada: %s', linha);
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

function [resposta, linhasTrace, linhasDados, linhasEventos] = ...
        aguardarPrefixoRegistrando(sp, prefixo, timeoutS, ...
        linhasTrace, linhasDados, linhasEventos)
inicio = tic;
while toc(inicio) < timeoutS
    if sp.NumBytesAvailable > 0
        linha = strtrim(readline(sp));
        if startsWith(linha, prefixo)
            resposta = linha;
            return;
        elseif startsWith(linha, "TRACE,")
            linhasTrace(end+1,1) = linha; %#ok<AGROW>
        elseif startsWith(linha, "DATA,")
            linhasDados(end+1,1) = linha; %#ok<AGROW>
        elseif startsWith(linha, "EVENT,")
            linhasEventos(end+1,1) = linha; %#ok<AGROW>
        end
    else
        pause(0.01);
    end
end
error('Timeout aguardando %s.', prefixo);
end

function dados = converterDados(linhas)
n = numel(linhas);
valores = zeros(n,20);
for k = 1:n
    partes = split(linhas(k), ',');
    assert(numel(partes) == 21 && partes(1) == "DATA", ...
        'Linha DATA invalida: %s', linhas(k));
    numeros = str2double(partes(2:end));
    assert(all(isfinite(numeros)), 'Valor DATA nao numerico: %s', linhas(k));
    valores(k,:) = numeros';
end
dados = array2table(valores, 'VariableNames', ...
    {'sequencia','tempo_s','referencia_C','Tp_C','Ta_C','W','modo_cooler', ...
    'beta','U_nominal','U_cooler','U_livre','U_saturado','e_seno_nominal', ...
    'e_seno_cooler','inovacao_nominal','inovacao_cooler','liberacao_us', ...
    'aquisicao_fim_us','controle_fim_us','atuacao_us'});
end

function trace = converterTrace(linhas)
n = numel(linhas);
tarefa = strings(n,1);
valores = zeros(n,15);
for k = 1:n
    partes = split(linhas(k), ',');
    assert(numel(partes) == 17 && partes(1) == "TRACE", ...
        'Linha TRACE invalida: %s', linhas(k));
    numeros = str2double(partes(3:end));
    assert(all(isfinite(numeros)), 'Valor TRACE nao numerico: %s', linhas(k));
    tarefa(k) = partes(2);
    valores(k,:) = numeros';
end
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

function fases = converterResumosCarga(linhas)
valores = zeros(numel(linhas),17);
for k = 1:numel(linhas)
    partes = split(linhas(k), ',');
    assert(numel(partes) == 19 && partes(1) == "SUMMARY" && ...
        partes(2) == "E5", 'Resumo E5 invalido: %s', linhas(k));
    numeros = str2double(partes(3:end));
    assert(all(isfinite(numeros)), ...
        'Resumo E5 contem valor nao numerico: %s', linhas(k));
    valores(k,:) = numeros';
end
fases = array2table(valores, 'VariableNames', ...
    {'fase','carga_pct','jobs_aquisicao','jobs_controle','jobs_atuacao', ...
    'jobs_supervisao','perdas_deadline','jitter_aquisicao_max_us', ...
    'jitter_supervisao_max_us','resposta_aquisicao_max_us', ...
    'resposta_controle_max_us','resposta_atuacao_max_us', ...
    'resposta_supervisao_max_us','e2e_max_us','ciclos_carga', ...
    'orcamento_total_us','janela_carga_max_us'});
assert(isequal(fases.fase, (0:height(fases)-1)'), ...
    'Ordem das fases E5 inconsistente.');
end

function plotarResumoCarga(fases, arquivo)
figura = figure('Visible', 'off', 'Color', 'w', ...
    'Name', 'E5 - resumo por carga');
limpeza = onCleanup(@() close(figura));
layout = tiledlayout(figura, 3, 1, ...
    'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(layout);
plot(ax1, fases.carga_pct, fases.jitter_aquisicao_max_us/1000, ...
    '-o', 'LineWidth', 1.5, 'DisplayName', 'Aquisição');
hold(ax1, 'on');
plot(ax1, fases.carga_pct, fases.jitter_supervisao_max_us/1000, ...
    '-s', 'LineWidth', 1.5, 'DisplayName', 'Supervisão');
grid(ax1, 'on');
ylabel(ax1, 'Jitter máximo (ms)');
legend(ax1, 'Location', 'best');

ax2 = nexttile(layout);
plot(ax2, fases.carga_pct, fases.resposta_aquisicao_max_us/1000, ...
    '-o', 'LineWidth', 1.5, 'DisplayName', 'Aquisição');
hold(ax2, 'on');
plot(ax2, fases.carga_pct, fases.resposta_supervisao_max_us/1000, ...
    '-s', 'LineWidth', 1.5, 'DisplayName', 'Supervisão');
plot(ax2, fases.carga_pct, fases.e2e_max_us/1000, ...
    '-^', 'LineWidth', 1.5, 'DisplayName', 'Fim a fim');
grid(ax2, 'on');
ylabel(ax2, 'Resposta máxima (ms)');
legend(ax2, 'Location', 'best');

ax3 = nexttile(layout);
orcamentoMedioMs = fases.orcamento_total_us ./ fases.ciclos_carga / 1000;
plot(ax3, fases.carga_pct, orcamentoMedioMs, ...
    '-o', 'LineWidth', 1.5, 'DisplayName', 'Orçamento por ciclo');
hold(ax3, 'on');
plot(ax3, fases.carga_pct, fases.janela_carga_max_us/1000, ...
    '-s', 'LineWidth', 1.5, 'DisplayName', 'Maior janela observada');
grid(ax3, 'on');
xlabel(ax3, 'Carga nominal (%)');
ylabel(ax3, 'Janela T_Carga (ms)');
legend(ax3, 'Location', 'best');

sgtitle(layout, 'E5 — efeito da carga de CPU no núcleo crítico');
exportgraphics(figura, arquivo, 'Resolution', 160);
clear limpeza
end

function metricas = resumir(dados, trace, hbEnviados, hbConfirmados, motivo)
erro = dados.referencia_C - dados.Tp_C;
e2e = dados.atuacao_us - dados.liberacao_us;
nomes = ["amostras"; "duracao_observada_s"; "Tp_media_C"; "Tp_min_C"; ...
    "Tp_max_C"; "Ta_media_C"; "erro_rmse_C"; "erro_iae_Cs"; ...
    "U_max"; "W_max"; "e2e_media_us"; "e2e_p95_us"; "e2e_p99_us"; ...
    "e2e_max_us"; "aquisicao_max_us"; "controle_max_us"; ...
    "atuacao_max_us"; "supervisao_max_us"; "bloqueio_adc_max_us"; ...
    "perdas_deadline"; "descartes_trace"; "heartbeats_enviados"; ...
    "heartbeats_confirmados"; "fim_normal"];
valores = [height(dados); max(dados.tempo_s); mean(dados.Tp_C); ...
    min(dados.Tp_C); max(dados.Tp_C); mean(dados.Ta_C); ...
    sqrt(mean(erro.^2)); sum(abs(erro))*5.715; max(dados.U_saturado); ...
    max(dados.W); mean(e2e); percentil(e2e,95); percentil(e2e,99); ...
    max(e2e); maxDaTarefa(trace,"AQUISICAO"); ...
    maxDaTarefa(trace,"CONTROLE"); maxDaTarefa(trace,"ATUACAO"); ...
    maxDaTarefa(trace,"SUPERVISAO"); max(trace.bloqueio_us); ...
    sum(trace.perdeu_deadline | trace.perdeu_deadline_fim_a_fim); ...
    max(trace.descartes_trace); hbEnviados; hbConfirmados; motivo=="FIM_NORMAL"];
unidades = ["contagem"; "s"; "degC"; "degC"; "degC"; "degC"; ...
    "degC"; "degC*s"; "PWM16"; "PWM12"; repmat("us",9,1); ...
    "contagem"; "contagem"; "contagem"; "contagem"; "booleano"];
metricas = table(nomes, valores, unidades, ...
    'VariableNames', {'metrica','valor','unidade'});
end

function valor = maxDaTarefa(trace, tarefa)
x = trace.execucao_us(trace.tarefa == tarefa);
assert(~isempty(x), 'Nao ha registros da tarefa %s.', tarefa);
valor = max(x);
end

function validarTarefa(trace, tarefa, quantidade)
sequencia = sort(trace.sequencia(trace.tarefa == tarefa));
assert(isequal(sequencia(:), (0:quantidade-1)'), ...
    'Sequencia %s inconsistente.', tarefa);
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
