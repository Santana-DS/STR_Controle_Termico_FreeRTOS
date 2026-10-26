function [dados, trace, metricas] = e4_coletar_congestionamento(porta, duracaoS, pastaResultados, mostrarGrafico)
%E4_COLETAR_CONGESTIONAMENTO Valida o desacoplamento da telemetria.

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
         'Para o E4 use e4_coletar_congestionamento("COM3",600).']);
end
if nargin < 3 || strlength(string(pastaResultados)) == 0
    pastaResultados = fullfile(raizBancada, 'resultados', 'reproduzidos', 'e4');
end
if nargin < 4 || isempty(mostrarGrafico)
    mostrarGrafico = true;
end

porta = string(porta);
pastaResultados = string(pastaResultados);
assert(duracaoS == 600, 'O E4 possui duracao fixa de 600 s.');
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
pong = aguardarPrefixo(sp, "ACK,PONG,E4_TELEMETRY", 5);
assert(pong == "ACK,PONG,E4_TELEMETRY", ...
    'Firmware conectado nao e o E4 de telemetria: %s', pong);

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

fprintf('\nE4: congestionamento de telemetria por %d s na %s.\n', duracaoS, porta);
fprintf('Fases: normal 0-120 s, congestionada 120-420 s, recuperacao 420-600 s.\n');
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
assert(strlength(motivoFim) > 0, 'Timeout aguardando o encerramento do E4.');
pause(0.20);
writeline(sp, "STATUS");
[statusFinal, linhasTrace, linhasDados, linhasEventos] = ...
    aguardarPrefixoRegistrando(sp, "STATUS,E4,", 5, ...
    linhasTrace, linhasDados, linhasEventos);
writeline(sp, "SUMMARY");
[resumoFinal, linhasTrace, linhasDados, linhasEventos] = ...
    aguardarPrefixoRegistrando(sp, "SUMMARY,E4,", 5, ...
    linhasTrace, linhasDados, linhasEventos);

dados = converterDados(linhasDados);
trace = converterTrace(linhasTrace);
resumo = converterResumoE4(resumoFinal);
metricas = resumir(dados, trace, heartbeatsEnviados, ...
    heartbeatsConfirmados, motivoFim, resumo);

instante = string(datetime('now','Format','yyyy-MM-dd_HHmmss'));
base = instante + "_E4_r01";
arquivoDados = fullfile(pastaResultados, base + "_dados.csv");
arquivoTrace = fullfile(pastaResultados, base + "_trace.csv");
arquivoMetricas = fullfile(pastaResultados, base + "_metricas.csv");
arquivoIntegridade = fullfile(pastaResultados, base + "_integridade.txt");
arquivoMonitor = fullfile(pastaResultados, base + "_monitor.png");
writetable(dados, arquivoDados);
writetable(trace, arquivoTrace);
writetable(metricas, arquivoMetricas);
if mostrarGrafico && isgraphics(monitor.figura)
    exportgraphics(monitor.figura, arquivoMonitor, 'Resolution', 160);
end
fid = fopen(arquivoIntegridade, 'w');
assert(fid >= 0, 'Nao foi possivel gravar o arquivo de integridade.');
fecharArquivo = onCleanup(@() fclose(fid));
fprintf(fid, 'motivo_fim=%s\n', motivoFim);
fprintf(fid, 'status_final=%s\n', statusFinal);
fprintf(fid, 'summary_final=%s\n', resumoFinal);
fprintf(fid, 'heartbeats_enviados=%d\n', heartbeatsEnviados);
fprintf(fid, 'heartbeats_confirmados=%d\n', heartbeatsConfirmados);
for k = 1:numel(linhasEventos)
    fprintf(fid, '%s\n', linhasEventos(k));
end
clear fecharArquivo

disp(metricas);
fprintf('Dados: %s\n', arquivoDados);
fprintf('Trace: %s\n', arquivoTrace);
fprintf('Metricas: %s\n', arquivoMetricas);
fprintf('Integridade: %s\n', arquivoIntegridade);
if mostrarGrafico && isfile(arquivoMonitor)
    fprintf('Grafico: %s\n', arquivoMonitor);
end

quantidadeEsperada = ceil(duracaoS / 5.715);
assert(motivoFim == "FIM_NORMAL", ...
    'E4 encerrado por %s em vez de FIM_NORMAL.', motivoFim);
assert(resumo.jobsAquisicao == quantidadeEsperada && ...
    resumo.jobsControle == quantidadeEsperada && ...
    resumo.jobsAtuacao == quantidadeEsperada, ...
    'O caminho critico nao concluiu as %d transacoes esperadas.', quantidadeEsperada);
assert(height(dados) < quantidadeEsperada && any(diff(dados.sequencia) > 1), ...
    'O E4 deve produzir lacunas observaveis na telemetria funcional.');
assert(dados.sequencia(1) == 0 && ...
    dados.sequencia(end) == quantidadeEsperada-1 && ...
    all(diff(dados.sequencia) > 0), ...
    'A telemetria recebida esta fora de ordem ou perdeu suas extremidades.');
assert(quantidadeEsperada-height(dados) == resumo.dadosDescartados, ...
    'A lacuna de dados nao coincide com os descartes contabilizados.');
assert(all(dados.Tp_C >= 5 & dados.Tp_C < 60) && ...
    all(dados.Ta_C >= 5 & dados.Ta_C < 60), ...
    'Temperatura fora da faixa segura de 5 a 60 graus C.');
assert(all(dados.U_saturado >= 0 & dados.U_saturado <= 65535) && ...
    all(dados.W >= 0 & dados.W <= 4095), 'Comando PWM fora da faixa.');
assert(all(dados.atuacao_us >= dados.controle_fim_us & ...
    dados.controle_fim_us >= dados.aquisicao_fim_us & ...
    dados.aquisicao_fim_us >= dados.liberacao_us), ...
    'Precedencia temporal inconsistente nos dados funcionais.');
assert(resumo.respostaFimAFimMaxUs <= 5715000, ...
    'Deadline fim a fim perdida durante o congestionamento.');
assert(~any(trace.jitter_us < 0 | trace.execucao_us < 0 | ...
    trace.resposta_us < 0 | trace.bloqueio_us < 0), ...
    'Trace contem tempos negativos.');
assert(~any(trace.perdeu_deadline | trace.perdeu_deadline_fim_a_fim), ...
    'Trace registrou perda de deadline.');
assert(max(trace.descartes_trace) == resumo.traceDescartado, ...
    'O trace recebido nao confirma o total final de descartes.');
assert(resumo.perdasDeadline == 0, ...
    'O resumo independente registrou perda de deadline.');
assert(resumo.aquisicaoMaxUs <= 600000 && resumo.controleMaxUs <= 100000 && ...
    resumo.atuacaoMaxUs <= 20000 && resumo.supervisaoMaxUs <= 500000, ...
    'Uma tarefa excedeu seu deadline local no resumo independente.');
assert(resumo.traceDescartado > 0 && resumo.dadosDescartados > 0, ...
    'O congestionamento nao saturou as filas de telemetria.');
assert(resumo.mensagemDescartada == 0, ...
    'Mensagens de evento foram descartadas durante o E4.');
assert(resumo.picoFilaTrace == 128 && resumo.picoFilaDados == 16, ...
    'As filas nao atingiram as capacidades previstas: trace=%d, dados=%d.', ...
    resumo.picoFilaTrace, resumo.picoFilaDados);
assert(any(startsWith(linhasEventos, "EVENT,CONGESTAO,INICIO,")) && ...
    any(startsWith(linhasEventos, "EVENT,CONGESTAO,FIM,")), ...
    'Os marcos de inicio e fim do congestionamento nao foram recebidos.');
assert(heartbeatsConfirmados == heartbeatsEnviados, ...
    'Heartbeats confirmados (%d) diferem dos enviados (%d).', ...
    heartbeatsConfirmados, heartbeatsEnviados);
partesStatus = split(statusFinal, ',');
assert(numel(partesStatus) == 17 && partesStatus(3) == "0" && ...
    partesStatus(4) == "1" && partesStatus(7) == "0" && ...
    partesStatus(8) == "0" && all(str2double(partesStatus(9:10)) == 0) && ...
    str2double(partesStatus(11)) <= 1, ...
    'Status final inseguro ou com filas pendentes: %s', statusFinal);
assert(str2double(partesStatus(12)) == resumo.traceDescartado && ...
    str2double(partesStatus(13)) == resumo.dadosDescartados && ...
    str2double(partesStatus(14)) == resumo.mensagemDescartada && ...
    all(str2double(partesStatus(15:17)) == 0), ...
    'O status final diverge do resumo ou indica perda critica: %s', statusFinal);
fprintf('\nE4 APROVADO: telemetria perdeu registros sem bloquear o caminho critico.\n');
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
monitor.figura = figure('Name', 'E4 - congestionamento de telemetria', ...
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
xline(monitor.axTemperatura, 120, '--', 'Início do congestionamento', ...
    'HandleVisibility', 'off');
xline(monitor.axTemperatura, 420, '--', 'Fim do congestionamento', ...
    'HandleVisibility', 'off');

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
xline(monitor.axAtuacao, 120, '--', 'HandleVisibility', 'off');
xline(monitor.axAtuacao, 420, '--', 'HandleVisibility', 'off');

limiteInicial = min(300, duracaoS);
xlim(monitor.axTemperatura, [0 limiteInicial]);
xlim(monitor.axAtuacao, [0 limiteInicial]);
sgtitle(layout, sprintf('E4 — telemetria normal/congestionada/recuperada: %d s', duracaoS));
setappdata(monitor.figura, 'ultimaSequenciaE4', []);
drawnow;
end

function atualizarMonitorTempoReal(monitor, partes)
sequencia = str2double(partes(2));
tempoS = str2double(partes(3));
referenciaC = str2double(partes(4));
TpC = str2double(partes(5));
TaC = str2double(partes(6));
WPercentual = 100 * str2double(partes(7)) / 4095;
UPercentual = 100 * str2double(partes(13)) / 65535;

ultimaSequencia = getappdata(monitor.figura, 'ultimaSequenciaE4');
if ~isempty(ultimaSequencia) && sequencia > ultimaSequencia + 1
    addpoints(monitor.referencia, NaN, NaN);
    addpoints(monitor.Tp, NaN, NaN);
    addpoints(monitor.Ta, NaN, NaN);
    addpoints(monitor.U, NaN, NaN);
    addpoints(monitor.W, NaN, NaN);
end
setappdata(monitor.figura, 'ultimaSequenciaE4', sequencia);

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

function resumo = converterResumoE4(linha)
partes = split(linha, ',');
assert(numel(partes) == 17 && partes(1) == "SUMMARY" && partes(2) == "E4", ...
    'Resumo E4 invalido: %s', linha);
v = str2double(partes(3:end));
assert(all(isfinite(v)), 'Resumo E4 contem valor nao numerico: %s', linha);
resumo = struct( ...
    'jobsAquisicao', v(1), 'jobsControle', v(2), ...
    'jobsAtuacao', v(3), 'jobsSupervisao', v(4), ...
    'perdasDeadline', v(5), 'respostaFimAFimMaxUs', v(6), ...
    'aquisicaoMaxUs', v(7), 'controleMaxUs', v(8), ...
    'atuacaoMaxUs', v(9), 'supervisaoMaxUs', v(10), ...
    'traceDescartado', v(11), 'dadosDescartados', v(12), ...
    'mensagemDescartada', v(13), 'picoFilaTrace', v(14), ...
    'picoFilaDados', v(15));
end

function metricas = resumir(dados, trace, hbEnviados, hbConfirmados, motivo, resumo)
erro = dados.referencia_C - dados.Tp_C;
e2e = dados.atuacao_us - dados.liberacao_us;
nomes = ["transacoes_criticas"; "dados_recebidos"; "dados_ausentes"; ...
    "cobertura_dados_pct"; "linhas_trace_recebidas"; "descartes_trace"; ...
    "descartes_dados"; "descartes_mensagens"; "pico_fila_trace"; ...
    "pico_fila_dados"; "jobs_supervisao"; "perdas_deadline"; ...
    "e2e_max_us"; "aquisicao_max_us"; "controle_max_us"; ...
    "atuacao_max_us"; "supervisao_max_us"; "e2e_p95_recebido_us"; ...
    "Tp_media_recebida_C"; "Tp_min_recebida_C"; "Tp_max_recebida_C"; ...
    "erro_rmse_recebido_C"; "U_max_recebido"; "W_max_recebido"; ...
    "heartbeats_enviados"; "heartbeats_confirmados"; "fim_normal"];
valores = [resumo.jobsAquisicao; height(dados); ...
    resumo.jobsAquisicao-height(dados); 100*height(dados)/resumo.jobsAquisicao; ...
    height(trace); resumo.traceDescartado; resumo.dadosDescartados; ...
    resumo.mensagemDescartada; resumo.picoFilaTrace; resumo.picoFilaDados; ...
    resumo.jobsSupervisao; resumo.perdasDeadline; resumo.respostaFimAFimMaxUs; ...
    resumo.aquisicaoMaxUs; resumo.controleMaxUs; resumo.atuacaoMaxUs; ...
    resumo.supervisaoMaxUs; percentil(e2e,95); mean(dados.Tp_C); ...
    min(dados.Tp_C); max(dados.Tp_C); sqrt(mean(erro.^2)); ...
    max(dados.U_saturado); max(dados.W); hbEnviados; hbConfirmados; ...
    motivo=="FIM_NORMAL"];
unidades = [repmat("contagem",3,1); "pct"; repmat("contagem",7,1); ...
    "contagem"; repmat("us",6,1); repmat("degC",4,1); ...
    "PWM16"; "PWM12"; repmat("contagem",2,1); "booleano"];
metricas = table(nomes, valores, unidades, ...
    'VariableNames', {'metrica','valor','unidade'});
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
